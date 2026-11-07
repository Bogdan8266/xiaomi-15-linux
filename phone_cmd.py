#!/usr/bin/env python3
import socket
import select
import sys
import time

def run_remote_command(cmd, timeout=15, print_output=True):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(('172.16.42.1', 23))
    
    # Read initial telnet handshake / prompt
    time.sleep(0.1)
    try:
        s.recv(1024)
    except:
        pass

    marker = "DONE_CODE_"
    full_cmd = f"{cmd}\necho {marker}$?\n"
    s.sendall(full_cmd.encode())

    start_time = time.time()
    s.setblocking(False)

    buffer = ""
    exit_code = None

    while True:
        if time.time() - start_time > timeout:
            if print_output:
                print("\n[TIMED OUT]")
            break

        r, _, _ = select.select([s], [], [], 0.2)
        if r:
            chunk = s.recv(4096)
            if not chunk:
                break
            text = chunk.decode(errors='replace')
            buffer += text
            if print_output:
                sys.stdout.write(text)
                sys.stdout.flush()

            # We look for a line starting with DONE_CODE_
            for line in buffer.splitlines():
                line = line.strip()
                if line.startswith(marker):
                    code_str = line[len(marker):]
                    try:
                        exit_code = int(code_str)
                    except:
                        pass
                    s.close()
                    return buffer, exit_code

    s.close()
    return buffer, exit_code

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: phone_cmd.py <command> [timeout]")
        sys.exit(1)
    timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    cmd = sys.argv[1]
    run_remote_command(cmd, timeout=timeout)
