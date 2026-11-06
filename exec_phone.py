#!/usr/bin/env python3
import sys
import socket
import time

def run_cmd(cmd: str, timeout=10):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(("172.16.42.1", 1337))

    marker = f"__END_{int(time.time()*1000)}__"
    full_cmd = f"{cmd}\necho {marker}\n"
    s.sendall(full_cmd.encode())

    out = b""
    deadline = time.time() + timeout
    marker_b = marker.encode()
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            out += chunk
            if marker_b in out:
                break
        except socket.timeout:
            break
    s.close()
    
    text = out.decode("utf-8", errors="replace")
    if marker in text:
        text = text[:text.index(marker)]
    return text.strip()

if __name__ == "__main__":
    timeout = 10
    args = sys.argv[1:]
    if len(args) > 1 and args[-1].isdigit():
        timeout = int(args[-1])
        cmd = " ".join(args[:-1])
    else:
        cmd = " ".join(args) if args else "uname -a"
    print(run_cmd(cmd, timeout))
