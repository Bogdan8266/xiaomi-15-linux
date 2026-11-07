#!/usr/bin/env python3
import os
import socket
import subprocess
import sys
import time

PMOS_DIR = "/home/bodya/pmos-dada"
PHONE_IP = "172.16.42.1"
HOST_IP = "172.16.42.2"
TELNET_PORT = 23
HTTP_PORT = 8000
BOOT_IMG = "/home/bodya/dada-mainline/boot-dada-mainline-step1-final.img"

def check_http_server():
    """Ensure HTTP server is running on port 8000 to serve files."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect(("127.0.0.1", HTTP_PORT))
        s.close()
        return True
    except:
        pass
    print("▶ Запуск локального HTTP-сервера на порту 8000...")
    subprocess.Popen(
        ["python3", "-m", "http.server", str(HTTP_PORT), "--bind", "0.0.0.0", "--directory", PMOS_DIR],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(1)
    return True

def is_phone_in_stage2():
    """Check if Stage 2 telnet is responding."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1.0)
    try:
        s.connect((PHONE_IP, TELNET_PORT))
        s.close()
        return True
    except:
        return False

def get_kernel_version():
    """Query running kernel version via telnet."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect((PHONE_IP, TELNET_PORT))
        time.sleep(0.1)
        s.recv(1024)
        s.sendall(b"uname -r\n")
        time.sleep(0.3)
        res = s.recv(1024).decode(errors="replace")
        s.close()
        for line in res.splitlines():
            line = line.strip()
            if "7.3" in line or "6.6" in line:
                return line
        return res.strip()
    except:
        return "unknown"

def check_fastboot():
    try:
        out = subprocess.check_output(["fastboot", "devices"], stderr=subprocess.DEVNULL).decode()
        return bool(out.strip())
    except:
        return False

def check_adb():
    try:
        out = subprocess.check_output(["adb", "devices"], stderr=subprocess.DEVNULL).decode()
        lines = [l for l in out.splitlines()[1:] if l.strip() and "offline" not in l]
        return bool(lines)
    except:
        return False

def stream_telnet_cmd(cmd, timeout=180.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect((PHONE_IP, TELNET_PORT))
    time.sleep(0.2)
    try:
        s.settimeout(0.3)
        s.recv(1024)
    except:
        pass

    s.settimeout(timeout)
    s.sendall(cmd.encode("utf-8") + b"\n")
    
    start = time.time()
    out = ""
    while time.time() - start < timeout:
        try:
            chunk = s.recv(2048)
            if not chunk:
                break
            text = chunk.decode("utf-8", errors="replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            out += text
            if "Phosh launch command completed" in out:
                break
        except socket.timeout:
            break
        except Exception as e:
            break
    s.close()
    return out

def main():
    print("=======================================================")
    print("   🚀 Xiaomi 15 (dada) — Автозапуск Mainline Linux     ")
    print("=======================================================")
    check_http_server()

    if is_phone_in_stage2():
        kver = get_kernel_version()
        print(f"✓ Телефон у мережі (172.16.42.1). Поточне ядро: {kver}")
        if "7.3" not in kver:
            print("⚠️ УВАГА: Зараз запущено старе GKI ядро 6.6 (без вбудованого драйвера тачскріна).")
            print("   Для роботи тачскріна потрібне Mainline-ядро 7.3-rc5!")
            print("   Переведіть телефон у Fastboot (затисніть Vol- та Power), і скрипт автоматично завантажить правильне ядро.")
            print("⏳ Очікування переходу у Fastboot...")
            for _ in range(45):
                if check_fastboot():
                    break
                time.sleep(1)

    if check_fastboot():
        print(f"▶ Знайдено Fastboot! Завантажуємо Mainline Linux ({os.path.basename(BOOT_IMG)})...")
        subprocess.run(["fastboot", "boot", BOOT_IMG], check=True)
        print("▶ Завантаження ядра в оперативну пам'ять... Очікуємо старт системи (~15-20 сек)...")
    elif check_adb():
        print("▶ Телефон у системі Android (ADB). Перезавантажуємо у Fastboot...")
        subprocess.run(["adb", "reboot", "bootloader"], check=True)
        time.sleep(4)
        if check_fastboot():
            print(f"▶ Завантажуємо Mainline Linux ({os.path.basename(BOOT_IMG)})...")
            subprocess.run(["fastboot", "boot", BOOT_IMG], check=True)
    elif not is_phone_in_stage2():
        print("⏳ Очікування підключення телефону...")
        print("   (Підключіть USB або переведіть у Fastboot: затисніть Vol- та Power)")
        found = False
        for _ in range(30):
            if is_phone_in_stage2():
                found = True
                break
            if check_fastboot():
                print(f"▶ Знайдено Fastboot пристрій! Завантажуємо Mainline Linux...")
                subprocess.run(["fastboot", "boot", BOOT_IMG], check=True)
                found = True
                break
            time.sleep(1)
        if not found:
            print("❌ Телефон не знайдено за 30 секунд. Спробуйте ще раз.")
            sys.exit(1)

    print("▶ Очікування готовності мережі 172.16.42.1:23...")
    connected = False
    for _ in range(40):
        if is_phone_in_stage2():
            connected = True
            break
        time.sleep(1)

    if not connected:
        print("❌ Не вдалося підключитися до 172.16.42.1:23.")
        sys.exit(1)

    kver = get_kernel_version()
    print(f"✓ З'єднання встановлено! Ядро: {kver}")
    print("▶ Вимикаємо сторожовий таймер...")
    try:
        s = socket.socket()
        s.settimeout(2.0)
        s.connect((PHONE_IP, TELNET_PORT))
        s.sendall(b"touch /tmp/keep\n")
        time.sleep(0.2)
        s.close()
    except Exception as e:
        print(f"Увага: {e}")

    print("▶ Синхронізація системного часу...")
    try:
        import datetime
        cur_utc = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        s = socket.socket()
        s.settimeout(2.0)
        s.connect((PHONE_IP, TELNET_PORT))
        s.sendall(f"date -u -s '{cur_utc}'\n".encode())
        time.sleep(0.2)
        s.close()
    except Exception as e:
        print(f"Увага: {e}")

    print("▶ Запуск Phosh Mobile Desktop (launch_phosh_mainline.sh)...")
    print("-------------------------------------------------------")
    stream_telnet_cmd(f"wget -q -O - http://{HOST_IP}:{HTTP_PORT}/launch_phosh_mainline.sh | sh", timeout=180.0)
    print("\n-------------------------------------------------------")
    print("🎉 Phosh активовано на екрані Xiaomi 15 (з підтримкою тачскріна synaptics_tcm)!")

if __name__ == "__main__":
    main()
