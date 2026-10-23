set_project("arduino_template")
set_version("0.1.0")

set_defaultplat("linux")
set_targetdir("$(builddir)")

local pdir = os.projectdir()

-- target board: "uno", "nano", "mega", "leonardo", "micro"
local default_board = "nano"

-- arduino libraries to compile: "Wire", "SPI", "EEPROM", "SoftwareSerial", "HID"
local arduino_libraries = {
  "Wire",
  "SPI",
  "EEPROM",
  "SoftwareSerial"
}

local boards = {
  uno = {
    name = "Arduino Uno",
    mcu = "atmega328p",
    f_cpu = "16000000L",
    board_def = "ARDUINO_AVR_UNO",
    variant = "standard",
    programmer = "arduino",
    upload_baud = 115200
  },
  nano = {
    name = "Arduino Nano",
    mcu = "atmega328p",
    f_cpu = "16000000L",
    board_def = "ARDUINO_AVR_NANO",
    variant = "eightanaloginputs",
    programmer = "arduino",
    upload_baud = 57600
  },
  mega = {
    name = "Arduino Mega 2560",
    mcu = "atmega2560",
    f_cpu = "16000000L",
    board_def = "ARDUINO_AVR_MEGA2560",
    variant = "mega",
    programmer = "wiring",
    upload_baud = 115200
  },
  leonardo = {
    name = "Arduino Leonardo",
    mcu = "atmega32u4",
    f_cpu = "16000000L",
    board_def = "ARDUINO_AVR_LEONARDO",
    variant = "leonardo",
    programmer = "avr109",
    upload_baud = 57600,
    usb_flags = {
      "USB_VID=0x2341",
      "USB_PID=0x8036",
      'USB_MANUFACTURER="Arduino LLC"',
      'USB_PRODUCT="Arduino Leonardo"'
    }
  },
  micro = {
    name = "Arduino Micro",
    mcu = "atmega32u4",
    f_cpu = "16000000L",
    board_def = "ARDUINO_AVR_MICRO",
    variant = "micro",
    programmer = "avr109",
    upload_baud = 57600,
    usb_flags = {
      "USB_VID=0x2341",
      "USB_PID=0x8037",
      'USB_MANUFACTURER="Arduino LLC"',
      'USB_PRODUCT="Arduino Micro"'
    }
  }
}

option("board")
  set_default(default_board)
  set_description("Target Arduino board (uno, nano, mega, leonardo, micro)")
  set_values("uno", "nano", "mega", "leonardo", "micro")
option_end()

option("mcu")
  set_default("")
  set_description("Override target MCU (e.g. atmega328p, atmega168, atmega2560, atmega32u4)")
option_end()

option("port")
  set_default("")
  set_description("Serial port for upload/monitoring (e.g. /dev/ttyUSB0, COM3)")
option_end()

option("baud")
    set_default("")
    set_description("Upload / monitor baud rate")
option_end()

option("bootloader")
  set_default("auto")
  set_description("Nano bootloader type (auto, old, optiboot)")
  set_values("auto", "old", "optiboot", "new")
option_end()

toolchain("avr")
  set_kind("standalone")

  on_load(function(toolchain)
    local bindir = (function()
      local env_avr = os.getenv("AVR_GCC") or os.getenv("AVR_PATH")
      if env_avr and #env_avr > 0 then
        if os.isfile(env_avr) then
          return path.directory(env_avr)
        elseif os.isdir(env_avr) then
          return env_avr
        end
      end

      local home = os.getenv("HOME") or ""
      local candidates = {
        path.join(home, ".arduino15/packages/arduino/tools/avr-gcc"),
        "/opt/arduino/hardware/tools/avr/bin",
        "/usr/bin",
        "/usr/local/bin"
      }

      for _, base in ipairs(candidates) do
        if os.isdir(base) then
          local match = os.files(path.join(base, "**/bin/avr-gcc"))
          if match and #match > 0 then
            import("core.base.semver")
            table.sort(match, function(a, b)
              local ver_a = a:match("(%d+%.%d+%.%d+)") or "0.0.0"
              local ver_b = b:match("(%d+%.%d+%.%d+)") or "0.0.0"
              return semver.compare(ver_a, ver_b) > 0
            end)
            return path.directory(match[1])
          elseif os.isfile(path.join(base, "avr-gcc")) then
            return base
          end
        end
      end
      return nil
    end)()

    if bindir then
        toolchain:add("runenvs", "PATH", bindir)
    end
  end)

  set_toolset("cc", "avr-gcc")
  set_toolset("cxx", "avr-g++")
  set_toolset("ld", "avr-gcc")
  set_toolset("ar", "avr-gcc-ar", "avr-ar")
  set_toolset("as", "avr-gcc")
  set_toolset("strip", "avr-strip")
  set_toolset("objcopy", "avr-objcopy")
  set_toolset("size", "avr-size")

  on_check(function(toolchain)
    return true
  end)
toolchain_end()

rule("arduino.board")
  on_load(function(target)
    import("core.project.config")

    local board_name = config.get("board") or default_board
    local board_info = boards[board_name] or boards["nano"]

    local mcu = config.get("mcu")
    if not mcu or #mcu == 0 then
      mcu = board_info.mcu
    end

    local mcu_def = "__AVR_" .. mcu:upper() .. "__"
    if mcu == "atmega328p" then
      mcu_def = "__AVR_ATmega328P__"
    elseif mcu == "atmega168" then
      mcu_def = "__AVR_ATmega168__"
    elseif mcu == "atmega2560" then
      mcu_def = "__AVR_ATmega2560__"
    elseif mcu == "atmega32u4" then
      mcu_def = "__AVR_ATmega32U4__"
    end

    target:set("languages", "gnu11", "gnuxx11")

    target:add("defines",
      "F_CPU=" .. board_info.f_cpu,
      "ARDUINO=10819",
      board_info.board_def,
      "ARDUINO_ARCH_AVR",
      mcu_def
    )

    if board_info.usb_flags then
      target:add("defines", board_info.usb_flags)
    end

    target:add("cxflags",
      "-mmcu=" .. mcu,
      "-Os",
      "-g",
      "-Wall",
      "-ffunction-sections",
      "-fdata-sections",
      "-flto",
      "-fno-fat-lto-objects",
      {force = true}
    )

    target:add("cxxflags",
      "-fpermissive",
      "-fno-exceptions",
      "-fno-threadsafe-statics",
      "-Wno-error=narrowing",
      {force = true}
    )

    target:add("asflags",
      "-mmcu=" .. mcu,
      "-x", "assembler-with-cpp",
      "-flto",
      {force = true}
    )

    target:add("ldflags",
      "-mmcu=" .. mcu,
      "-Os",
      "-g",
      "-flto",
      "-fuse-linker-plugin",
      "-Wl,--gc-sections",
      "-lm",
      {force = true}
    )

    -- base includes
    local avr_core_dir = path.join(pdir, "firmware/lib/ArduinoCore-avr")
    target:add("includedirs",
      path.join(avr_core_dir, "cores/arduino"),
      path.join(avr_core_dir, "variants", board_info.variant),
      path.join(pdir, "firmware")
    )

    -- enabled Arduino core libraries
    for _, lib in ipairs(arduino_libraries) do
      local lib_src = path.join(avr_core_dir, "libraries", lib, "src")
      local lib_root = path.join(avr_core_dir, "libraries", lib)
      if os.isdir(lib_src) then
        target:add("includedirs", lib_src)
      elseif os.isdir(lib_root) then
        target:add("includedirs", lib_root)
      end
    end
  end)
rule_end()

add_rules("plugin.compile_commands.autoupdate", {outputdir = "build", lsp = "clangd"})

after_config(function()
  import("core.base.task")
  task.run("project", {kind = "compile_commands", outputdir = "build", lsp = "clangd"})
end)

target("arduino_core")
  set_kind("static")
  set_default(false)
  set_targetdir("$(builddir)")
  set_toolchains("avr")
  add_rules("arduino.board")

  -- core sources
  add_files(
    "firmware/lib/ArduinoCore-avr/cores/arduino/**.c",
    "firmware/lib/ArduinoCore-avr/cores/arduino/**.cpp",
    "firmware/lib/ArduinoCore-avr/cores/arduino/**.S"
  )

  -- bundled libraries
  for _, lib in ipairs(arduino_libraries) do
    local lib_base = path.join(pdir, "firmware/lib/ArduinoCore-avr/libraries", lib)
    local candidates = {
      path.join(lib_base, "src/**.c"),
      path.join(lib_base, "src/**.cpp"),
      path.join(lib_base, "*.c"),
      path.join(lib_base, "*.cpp")
    }
    for _, pat in ipairs(candidates) do
      local matched = os.files(pat)
      if matched and #matched > 0 then
        add_files(pat)
      end
    end
  end
target_end()

target("firmware")
  set_kind("binary")
  set_default(true)
  set_filename("firmware.elf")
  set_targetdir("$(builddir)")
  set_toolchains("avr")
  add_rules("arduino.board")
  add_deps("arduino_core")

  -- source files in firmware/
  local user_patterns = {
    "firmware/*.cpp",
    "firmware/*.c",
    "firmware/src/**.cpp",
    "firmware/src/**.c"
  }
  for _, pat in ipairs(user_patterns) do
    local matched = os.files(path.join(pdir, pat))
    if matched and #matched > 0 then
      add_files(pat)
    end
  end

  after_build(function(target)
    import("core.project.config")

    local outdir = target:targetdir()
    local elf_path = target:targetfile()
    local hex_path = path.join(outdir, "firmware.hex")

    print("Generating Intel HEX: %s", hex_path)
    os.execv("avr-objcopy", {
      "-O", "ihex",
      "-R", ".eeprom",
      elf_path,
      hex_path
    })

    local board_name = config.get("board") or default_board
    local board_info = boards[board_name] or boards["nano"]
    local mcu = config.get("mcu")
    if not mcu or #mcu == 0 then
      mcu = board_info.mcu
    end

    print("Firmware memory usage:")
    try {
      function()
        os.execv("avr-size", {"-C", "--mcu=" .. mcu, elf_path})
      end,
      catch {
        function()
          try {
            function()
              os.execv("avr-size", {elf_path})
            end
          }
        end
      }
    }
  end)
target_end()

task("flash")
  set_menu({
    usage = "xmake flash [options]",
    description = "Flash firmware to Arduino board (Uno, Nano, Mega, Leonardo, Micro)",
    options = {
      {'t', "target", "kv", nil, "Target board type (uno, nano, mega, leonardo, micro)"},
      {'p', "port", "kv", nil, "Serial port (e.g. /dev/ttyUSB0, COM3)"},
      {'b', "baud", "kv", nil, "Upload baud rate (e.g. 57600, 115200)"},
      {'B', "bootloader", "kv", nil, "Nano bootloader type (auto, old, optiboot)"},
      {'m', "mcu", "kv", nil, "Microcontroller override (e.g. atmega328p, atmega168)"}
    }
  })

  on_run(function()
    import("core.base.option")
    import("core.project.config")

    os.exec("xmake build firmware")

    local board_arg = option.get("target") or config.get("board") or default_board
    local port_arg = option.get("port") or config.get("port")
    local baud_arg = option.get("baud") or config.get("baud")
    local boot_arg = option.get("bootloader") or config.get("bootloader")
    local mcu_arg = option.get("mcu") or config.get("mcu")

    local flasher_script = path.join(pdir, "tools/flasher.py")
    local args = {flasher_script, "-t", board_arg}

    if port_arg and #tostring(port_arg) > 0 then
      table.insert(args, "-p")
      table.insert(args, tostring(port_arg))
    end
    if baud_arg and #tostring(baud_arg) > 0 then
      table.insert(args, "-b")
      table.insert(args, tostring(baud_arg))
    end
    if boot_arg and #tostring(boot_arg) > 0 and boot_arg ~= "auto" then
      table.insert(args, "-B")
      table.insert(args, tostring(boot_arg))
    end
    if mcu_arg and #tostring(mcu_arg) > 0 then
      table.insert(args, "-m")
      table.insert(args, tostring(mcu_arg))
    end

    os.execv("python3", args)
  end)
task_end()

task("monitor")
  set_menu({
    usage = "xmake monitor [options]",
    description = "Open serial monitor to connected Arduino board",
    options = {
      {'p', "port", "kv", nil, "Serial port (e.g. /dev/ttyUSB0)"},
      {'b', "baud", "kv", 9600, "Serial baud rate (default: 9600)"}
    }
  })

  on_run(function()
    import("core.base.option")
    import("core.project.config")

    local port = option.get("port") or config.get("port")
    local baud = tostring(option.get("baud") or config.get("baud") or 9600)
    local miniterm = path.join(pdir, "tools/miniterm.py")

    local args = {miniterm, "--exit-char", "3", "--rts=0", "--dtr=0"}
    if port and #port > 0 then
      table.insert(args, port)
    else
      table.insert(args, "-") -- miniterm prompts or lists ports when "-"
    end
    table.insert(args, baud)

    os.execv("python3", args)
  end)
task_end()
