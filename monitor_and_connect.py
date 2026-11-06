#!/usr/bin/env python3
import subprocess
import time
import socket
import sys
import os

print("[1/4] Checking device state...")
res_fb = subprocess.run(["fastboot", "devices"], capture_output=True, text=True)
if "fastboot" not in res_fb.stdout:
    res_adb = subprocess.run(["adb", "devices"], capture_output=True, text=True)
    if "device" in res_adb.stdout:
        print("Device in ADB, rebooting to bootloader...")
        subprocess.run(["adb", "reboot", "bootloader"], check=True)
        time.sleep(3)

print("[2/4] Flashing ksu_stage2_final.img (80 modules: UFS + Full USB + Flash Logger) to init_boot_b...")
subprocess.run(["fastboot", "flash", "init_boot_b", "/home/bodya/pmos-dada/ksu_stage2_final.img"], check=True)

print("[3/4] Setting active slot to b...")
subprocess.run(["fastboot", "set_active", "b"], check=True)

for var in ['current-slot', 'slot-unbootable:b', 'slot-retry-count:b']:
    res_var = subprocess.run(['fastboot', 'getvar', var], capture_output=True, text=True)
    print(" ", res_var.stdout.strip(), res_var.stderr.strip())

print("[4/4] Rebooting into slot b...")
subprocess.run(["fastboot", "reboot"], check=True)

print("\n=== MONITORING FOR LINUX SHELL (CDC-NCM / Telnet / Netcat) ===")
print("Watching for USB network interface and ports 23 / 1337 on 172.16.42.1...")

start_time = time.time()
connected = False

while time.time() - start_time < 90:
    elapsed = int(time.time() - start_time)
    
    # Check for new network interfaces
    try:
        ip_out = subprocess.run(["ip", "-o", "link", "show"], capture_output=True, text=True).stdout
        ifaces = [line.split(": ")[1].split("@")[0] for line in ip_out.splitlines()]
        usb_ifaces = [i for i in ifaces if i.startswith("usb") or i.startswith("enx")]
        if usb_ifaces:
            print(f"[{elapsed}s] Found USB network interface(s): {usb_ifaces}")
    except Exception as e:
        pass

    # Try connecting to port 23 (telnet) or 1337 (netcat)
    for port in [23, 1337]:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(0.8)
            s.connect(("172.16.42.1", port))
            print(f"\n🎉🎉🎉 SUCCESS! CONNECTED TO PORT {port} ON 172.16.42.1! 🎉🎉🎉\n")
            
            # Send keepalive immediately
            s.sendall(b"touch /tmp/keep\n")
            time.sleep(0.2)
            s.sendall(b"uname -a; echo '--- UPTIME ---'; uptime; echo '--- LOG ---'; cat /tmp/stage2.log; echo '--- UDC ---'; ls -la /sys/class/udc\n")
            
            time.sleep(1)
            response = b""
            while True:
                try:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    response += chunk
                except socket.timeout:
                    break
            
            print(response.decode("utf-8", errors="replace"))
            connected = True
            s.close()
            break
        except (socket.timeout, ConnectionRefusedError, OSError):
            pass
            
    if connected:
        break
        
    time.sleep(1)
    if elapsed % 10 == 0:
        print(f"[{elapsed}s] Waiting for network connection...")

if not connected:
    print("\n[!] Connection timed out after 90 seconds.")
    print("Checking USB devices on host:")
    subprocess.run(["lsusb"])
