#!/usr/bin/env python3
import os
import socket
import sys
import time

def run_command(cmd, timeout=None, port=23):
    if timeout is None:
        timeout = float(os.environ.get("CMD_TIMEOUT", 15.0))
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect(("172.16.42.1", port))
    except Exception as e:
        print(f"Connection failed: {e}")
        return None

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
            text = chunk.decode("utf-8", errors="replace")
            out += text
            stripped = out.strip()
            if stripped.endswith("~ #") or stripped.endswith("~ $") or out.endswith("\n# ") or out.endswith("\n$ "):
                break
        except socket.timeout:
            break
        except Exception:
            break
    s.close()
    return out

if __name__ == "__main__":
    cmd = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "uptime"
    res = run_command(cmd)
    if res:
        print(res)
