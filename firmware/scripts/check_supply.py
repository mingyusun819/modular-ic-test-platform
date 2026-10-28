"""Read the board's supply telemetry without changing its configuration."""
import sys
import time
import serial

with serial.Serial(sys.argv[1], 115200, timeout=1.5) as port:
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        line = port.readline().decode("ascii", errors="replace").strip()
        if line:
            print(line)
