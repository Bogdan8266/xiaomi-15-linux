import os, termios, time

try:
    fd = os.open("/dev/ttyHS0", os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    print("Initial attrs cflag:", hex(attrs[2]), "ispeed:", attrs[4], "ospeed:", attrs[5])

    for baud_name, baud in [("115200", termios.B115200), ("3000000", 3000000)]:
        print(f"--- Testing at {baud_name} ---")
        attrs = termios.tcgetattr(fd)
        attrs[4] = baud
        attrs[5] = baud
        attrs[2] &= ~termios.CRTSCTS
        termios.tcsetattr(fd, termios.TCSANOW, attrs)

        # Wakeup byte
        os.write(fd, bytes([0xFD]))
        time.sleep(0.05)
        # HCI reset: 01 03 0c 00
        os.write(fd, bytes([0x01, 0x03, 0x0C, 0x00]))
        # EDL version: 01 00 fc 01 00
        os.write(fd, bytes([0x01, 0x00, 0xFC, 0x01, 0x00]))
        time.sleep(0.15)
        try:
            data = os.read(fd, 128)
            print("Received bytes:", data.hex())
        except BlockingIOError:
            print("No response (timeout)")

    os.close(fd)
except Exception as e:
    print("Error:", e)
