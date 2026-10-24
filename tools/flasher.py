#!/usr/bin/env python3
import argparse
import glob
import os
import pathlib
import shutil
import subprocess
import sys
import time

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PYSERIAL_DIR = REPO_ROOT / "tools" / "pyserial"
if PYSERIAL_DIR.is_dir():
    sys.path.insert(0, str(PYSERIAL_DIR))

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.stderr.write("Error: PySerial could not be loaded.\n")
    sys.exit(1)


BOARD_CONFIGS = {
    "uno": {
        "name": "Arduino Uno",
        "mcu": "atmega328p",
        "programmer": "arduino",
        "baud": 115200,
        "reset": "dtr",
    },
    "nano": {
        "name": "Arduino Nano",
        "mcu": "atmega328p",
        "programmer": "arduino",
        "baud": 57600,
        "reset": "dtr",
    },
    "mega": {
        "name": "Arduino Mega 2560",
        "mcu": "atmega2560",
        "programmer": "wiring",
        "baud": 115200,
        "reset": "dtr",
    },
    "leonardo": {
        "name": "Arduino Leonardo",
        "mcu": "atmega32u4",
        "programmer": "avr109",
        "baud": 57600,
        "reset": "1200bps",
    },
    "micro": {
        "name": "Arduino Micro",
        "mcu": "atmega32u4",
        "programmer": "avr109",
        "baud": 57600,
        "reset": "1200bps",
    },
}


def find_avrdude():
    avrdude_bin = shutil.which("avrdude")
    avrdude_conf = None

    if not avrdude_bin:
        home = pathlib.Path.home()
        search_dirs = [
            home / ".arduino15" / "packages" / "arduino" / "tools" / "avrdude",
            pathlib.Path("/opt/arduino/hardware/tools/avr/bin"),
            pathlib.Path("/usr/local/bin"),
            pathlib.Path("/usr/bin"),
        ]
        for base in search_dirs:
            if base.is_dir():
                matches = list(base.glob("**/bin/avrdude"))
                if matches:
                    avrdude_bin = str(matches[0])
                    break
                candidate = base / "avrdude"
                if candidate.is_file():
                    avrdude_bin = str(candidate)
                    break

    if not avrdude_bin:
        print("Error: Can't find avrdude.", file=sys.stderr)
        sys.exit(1)

    bin_dir = pathlib.Path(avrdude_bin).resolve().parent
    potential_confs = [
        bin_dir.parent / "etc" / "avrdude.conf",
        bin_dir / "avrdude.conf",
        pathlib.Path("/etc/avrdude.conf"),
        pathlib.Path("/etc/avrdude/avrdude.conf"),
    ]
    for c in potential_confs:
        if c.is_file():
            avrdude_conf = str(c)
            break

    return avrdude_bin, avrdude_conf


def reset_leonardo(port_name):
    print(f"Triggering 1200-bps touch reset on {port_name}...")
    before_ports = {p.device for p in serial.tools.list_ports.comports()}
    try:
        ser = serial.Serial(port_name, baudrate=1200)
        ser.close()
    except Exception as e:
        print(f"Warning during 1200-bps touch: {e}")

    # wait up to 5 secs for bootloader port
    timeout = 5.0
    start = time.time()
    while time.time() - start < timeout:
        time.sleep(0.25)
        current_ports = {p.device for p in serial.tools.list_ports.comports()}
        diff = current_ports - before_ports
        if diff:
            new_port = list(diff)[0]
            print(f"Bootloader port detected: {new_port}")
            time.sleep(0.2)
            return new_port
        if port_name in current_ports:
            return port_name

    return port_name


def auto_detect_port():
    candidates = []
    for port in serial.tools.list_ports.comports():
        if port.device.startswith("/dev/ttyS") and port.description == "n/a":
            continue
        candidates.append(port)
    if not candidates:
        print("Error: No serial ports detected. Please connect your board or specify --port.", file=sys.stderr)
        sys.exit(1)

    if len(candidates) == 1:
        selected = candidates[0].device
        print(f"Auto-selected serial port: {selected} ({candidates[0].description})")
        return selected

    for cand in candidates:
        desc = f"{cand.description or ''} {cand.hwid or ''}".lower()
        if any(keyword in desc for keyword in ["arduino", "ch340", "ft232", "cp210", "2341:", "2a03:", "1a86:"]):
            print(f"Auto-selected port based on identifier: {cand.device} ({cand.description})")
            return cand.device

    print("Multiple serial ports detected:", file=sys.stderr)
    for cand in candidates:
        print(f"  - {cand.device} ({cand.description} / {cand.hwid})", file=sys.stderr)
    print("Please specify a port with --port=<port>", file=sys.stderr)
    sys.exit(1)



def flash(board_key, port, baud, hex_file, mcu=None, programmer=None, bootloader="auto"):
    if not os.path.isfile(hex_file):
        print(f"Error: Firmware hex file not found at '{hex_file}'", file=sys.stderr)
        sys.exit(1)

    avrdude_bin, avrdude_conf = find_avrdude()
    board_config = BOARD_CONFIGS.get(board_key.lower(), BOARD_CONFIGS["nano"])
    target_mcu = mcu or board_config["mcu"]
    target_prog = programmer or board_config["programmer"]

    target_port = port or auto_detect_port()

    def reset_avr_via_dtr():
        try:
            ser = serial.Serial(target_port, baudrate=1200)
            ser.dtr = False
            ser.rts = False
            time.sleep(0.05)
            ser.dtr = True
            ser.rts = True
            time.sleep(0.1)
            ser.dtr = False
            ser.rts = False
            time.sleep(0.05)
            ser.close()
            time.sleep(0.15)
        except Exception:
            pass


    if board_config.get("reset") == "1200bps":
        target_port = reset_leonardo(target_port)
    elif board_config.get("reset") == "dtr":
        reset_avr_via_dtr()

    baud_candidates = []
    if baud:
        baud_candidates = [int(baud)]
    elif board_key.lower() == "nano":
        if target_mcu == "atmega168":
            baud_candidates = [19200]
        elif bootloader == "old":
            baud_candidates = [57600]
        elif bootloader in ["new", "optiboot"]:
            baud_candidates = [115200]
        else:
            baud_candidates = [57600, 115200]
    else:
        baud_candidates = [board_config["baud"]]

    success = False
    for i, try_baud in enumerate(baud_candidates):
        if i > 0:
            print(f"\nAttempt at {baud_candidates[i-1]} baud failed. Retrying at {try_baud} baud...")
            if board_config.get("reset") == "dtr":
                reset_avr_via_dtr(target_port)
            time.sleep(0.2)

        args = [
            avrdude_bin,
            "-v",
            "-p", target_mcu,
            "-c", target_prog,
            "-P", target_port,
            "-b", str(try_baud),
            "-D",
            f"-Uflash:w:{hex_file}:i",
        ]
        if avrdude_conf:
            args.extend(["-C", avrdude_conf])

        print(f"\nFlashing via avrdude on {target_port} (MCU: {target_mcu}, programmer: {target_prog}, baud: {try_baud})...")
        res = subprocess.run(args)
        if res.returncode == 0:
            success = True
            break

    if not success:
        print("Flashing failed with attempted baud rate(s).", file=sys.stderr)
        sys.exit(1)

    print("\nFlashing completed!")


def main():
    parser = argparse.ArgumentParser(description="Unified AVR Arduino Flasher.")
    parser.add_argument("-t", "--target", default="nano", choices=list(BOARD_CONFIGS.keys()), help="Target board type")
    parser.add_argument("-p", "--port", default=None, help="Serial port (e.g. /dev/ttyUSB0, COM3)")
    parser.add_argument("-b", "--baud", type=int, default=None, help="Upload baud rate")
    parser.add_argument("-B", "--bootloader", default="auto", choices=["auto", "old", "new", "optiboot"], help="Bootloader type")
    parser.add_argument("-m", "--mcu", default=None, help="Microcontroller override (e.g. atmega328p, atmega168, atmega2560, atmega32u4)")
    parser.add_argument("--programmer", default=None, help="avrdude programmer override (e.g. arduino, wiring, avr109)")
    parser.add_argument("--hex", default=None, help="Path to firmware hex file")

    args = parser.parse_args()

    hex_path = args.hex
    if not hex_path:
        build_dir = REPO_ROOT / "build"
        default_hex = build_dir / "firmware.hex"
        if default_hex.is_file():
            hex_path = str(default_hex)
        else:
            candidates = list(build_dir.glob("*.hex"))
            if candidates:
                hex_path = str(candidates[0])
            else:
                hex_path = str(default_hex)

    flash(
        board_key=args.target,
        port=args.port,
        baud=args.baud,
        hex_file=hex_path,
        mcu=args.mcu,
        programmer=args.programmer,
        bootloader=args.bootloader,
    )


if __name__ == "__main__":
    main()
