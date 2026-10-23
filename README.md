# Arduino xmake Template

Template for building, flashing, and monitoring AVR Arduino projects using xmake instead of the Arduino IDE.

Tested on Linux (Fedora), probably works on Windows.

## Requirements

- `xmake` (>= 2.8)
- `avr-gcc` / `avr-g++` and `avr-libc`
- `avrdude`
- `python3`

Initialize git submodules for the bundled Arduino AVR core and PySerial:

```bash
git submodule update --init --recursive
```

## Quick Start

```bash
xmake f --board=nano -c # see available boards below
xmake build
xmake flash # auto-detects port and baud
xmake monitor
```

## Manual board Configuration

Supported boards: `nano`, `uno`, `mega` (2560), `leonardo`, `micro`.

You can edit the top of `xmake.lua`:

```lua
local default_board = "nano"

local arduino_libraries = {
  "Wire",
  "SPI",
  "EEPROM",
  "SoftwareSerial"
}
```

Or you can switch target boards/MCU without editing through the CLI:

```bash
xmake f --board=uno -c # Arduino Uno
xmake f --board=mega -c # Arduino Mega 2560
xmake f --board=nano --mcu=atmega168 -c # Arduino Nano with ATmega168
```

## Flashing

The flasher automatically finds the connected USB serial port. You can also specify it manually.

```bash
xmake flash # auto port
xmake flash -t nano -p /dev/ttyUSB0 -b 57600 
xmake flash -t mega -p /dev/ttyACM0 
xmake flash -B optiboot # force optiboot / new bootloader
```

## Serial monitor

Uses `tools/miniterm.py` with fallback to bundled PySerial.

```bash
xmake monitor # default 9600 baud, auto port
xmake monitor -p /dev/ttyUSB0 -b 115200
```

## Source structure

Put your code in `firmware/`. The default entrypoint is at `firmware/main.cpp`

xmake generates `build/compile_commands.json` for clangd on each build/configuration.