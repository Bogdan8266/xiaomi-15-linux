#!/usr/bin/env python3
import socket
import subprocess
import time
import sys

def telnet_cmd(cmd, timeout=10.0):
    try:
        s = socket.socket()
        s.settimeout(timeout)
        s.connect(("172.16.42.1", 23))
        time.sleep(0.1)
        try:
            s.settimeout(0.2)
            s.recv(1024)
        except:
            pass
        s.settimeout(timeout)
        s.sendall(cmd.encode("utf-8") + b"\n")
        out = ""
        start = time.time()
        while time.time() - start < timeout:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                out += chunk.decode("utf-8", errors="replace")
                if out.strip().endswith(("#", "$")):
                    break
            except socket.timeout:
                break
            except Exception:
                break
        s.close()
        return out
    except Exception as e:
        return None

print("=== [1/4] Triggering Clean Reboot into Slot B ===")
try:
    s = socket.socket()
    s.settimeout(2.0)
    s.connect(("172.16.42.1", 23))
    s.sendall(b"echo b > /proc/sysrq-trigger\n")
    s.close()
except:
    pass

print("=== [2/4] Waiting for Stage 2 Reconnect on 172.16.42.1:23 ===")
start = time.time()
connected = False
while time.time() - start < 45:
    res = telnet_cmd("uptime", timeout=1.0)
    if res and "up" in res:
        print(f"🎉 Connected after {int(time.time() - start)}s! Phone is alive:")
        print(res.strip())
        connected = True
        break
    time.sleep(1)

if not connected:
    print("Failed to reconnect to phone within 45s!")
    sys.exit(1)

# Touch keepalive
telnet_cmd("touch /tmp/keep")

print("=== [3/4] Loading Patched DRM Stack (always_complete_flip + anti_panic) ===")
deploy_cmd = """
rm -rf /tmp/drm
mkdir -p /tmp/drm
wget -q http://172.16.42.2:8000/drm_all.tar.gz -O /tmp/drm_all.tar.gz
tar -xzf /tmp/drm_all.tar.gz -C /tmp/drm/
wget -q http://172.16.42.2:8000/load_drm_smart.sh -O /tmp/drm/load_drm_smart.sh
chmod +x /tmp/drm/load_drm_smart.sh
/tmp/drm/load_drm_smart.sh
"""
out = telnet_cmd(deploy_cmd, timeout=20.0)
print(out)

print("=== [4/4] Deploying Desktop Rootfs & Starting Weston ===")
rootfs_cmd = """
mkdir -p /rootfs
mountpoint -q /rootfs || mount -t tmpfs -o size=3G tmpfs /rootfs
wget -q -O - http://172.16.42.2:8000/alpine-desktop-ready.tar.gz | tar -xz -C /rootfs
mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/dev/pts /rootfs/run /rootfs/tmp
mountpoint -q /rootfs/dev || mount --bind /dev /rootfs/dev
mountpoint -q /rootfs/proc || mount -t proc none /rootfs/proc
mountpoint -q /rootfs/sys || mount -t sysfs none /rootfs/sys
mountpoint -q /rootfs/dev/pts || mount -t devpts none /rootfs/dev/pts
mkdir -p /dev/input && mknod -m 666 /dev/input/event0 c 13 64 2>/dev/null || true
wget -q http://172.16.42.2:8000/start_desktop.sh -O /rootfs/start_desktop.sh
chmod +x /rootfs/start_desktop.sh
chroot /rootfs /start_desktop.sh > /tmp/desktop.log 2>&1 &
sleep 3
ps | grep -E 'weston|seatd'
"""
out = telnet_cmd(rootfs_cmd, timeout=60.0)
print(out)
