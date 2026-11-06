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

def stream_telnet_cmd(cmd, timeout=120.0):
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
            if "ALL_PHOSH_READY" in out:
                break
        except socket.timeout:
            break
        except Exception as e:
            break
    s.close()
    return out

def main():
    print("=======================================================")
    print("   🚀 Xiaomi 15 (dada) — Автозапуск Linux (Phosh)     ")
    print("=======================================================")
    check_http_server()

    if is_phone_in_stage2():
        print("✓ Телефон вже в режимі Stage 2 Linux (172.16.42.1)!")
    elif check_fastboot():
        print("▶ Телефон у Fastboot. Перемикаємо слот на B і перезавантажуємо...")
        subprocess.run(["fastboot", "set_active", "b"], check=True)
        subprocess.run(["fastboot", "reboot"], check=True)
        print("▶ Чекаємо на завантаження ядра Linux (~15-20 сек)...")
    elif check_adb():
        print("▶ Телефон у системі Android (ADB). Перезавантажуємо у Fastboot...")
        subprocess.run(["adb", "reboot", "bootloader"], check=True)
        time.sleep(4)
        print("▶ Перемикаємо слот на B і перезавантажуємо...")
        subprocess.run(["fastboot", "set_active", "b"], check=True)
        subprocess.run(["fastboot", "reboot"], check=True)
        print("▶ Чекаємо на завантаження ядра Linux (~15-20 сек)...")
    else:
        print("⏳ Очікування підключення телефону...")
        print("   (Підключіть USB або переведіть у Fastboot: затисніть Vol- та Power)")
        found = False
        for _ in range(30):
            if is_phone_in_stage2():
                found = True
                break
            if check_fastboot():
                print("▶ Знайдено Fastboot пристрій! Перемикаємо на слот B...")
                subprocess.run(["fastboot", "set_active", "b"], check=True)
                subprocess.run(["fastboot", "reboot"], check=True)
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

    print("✓ З'єднання встановлено!")
    print("▶ Вимикаємо сторожовий таймер (/tmp/keep)...")
    try:
        s = socket.socket()
        s.settimeout(2.0)
        s.connect((PHONE_IP, TELNET_PORT))
        s.sendall(b"touch /tmp/keep\n")
        time.sleep(0.2)
        s.close()
    except Exception as e:
        print(f"Увага: {e}")

    print("▶ Розгортання та запуск Phosh (boot_phosh_all.sh)...")
    print("-------------------------------------------------------")
    stream_telnet_cmd(f"wget -q -O - http://{HOST_IP}:{HTTP_PORT}/boot_phosh_all.sh | sh", timeout=180.0)
    print("\n-------------------------------------------------------")
    print("🎉 Готово! Phosh активовано на екрані Xiaomi 15!")

if __name__ == "__main__":
    main()
