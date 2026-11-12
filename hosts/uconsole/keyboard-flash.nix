# uconsole-keyboard-flash: flash the uConsole keyboard MCU (STM32, LeafLabs
# maple bootloader, USB 1eaf:0024; DFU 1eaf:0003) with j1n6/qmk-uconsole or
# restore ClockworkPi's stock firmware.
#
# Packages what the upstream instructions do by hand on Debian, without their
# prebuilt glibc binaries: `upload-reset` (stock bundle's 161-line C tool that
# kicks the stock firmware into its bootloader over the CDC-ACM serial port) is
# built from source, and dfu-util comes from nixpkgs.
#
#   sudo uconsole-keyboard-flash qmk            # QMK v2.1.1, default build
#   sudo uconsole-keyboard-flash qmk-no-tap-hold
#   sudo uconsole-keyboard-flash stock          # ClockworkPi stock firmware
#   sudo uconsole-keyboard-flash ./other.bin
#
# Nothing runs at deploy time; flashing is always a manual step. The keyboard
# is its own USB device, so a failed flash leaves the rest of the system (and
# SSH) working. Recovery: short S1 on the keyboard PCB, then flash `stock`.
{
  lib,
  stdenv,
  fetchurl,
  writeShellApplication,
  dfu-util,
  coreutils,
  symlinkJoin,
}:
let
  qmkVersion = "2.1.1";

  stockBundle = fetchurl {
    url = "https://github.com/clockworkpi/uConsole/raw/b9530302fb5a1aba5af15b9181b61a5efa2f3c80/Bin/uconsole_keyboard_flash.tar.gz";
    hash = "sha256-XHK7zHRx2loHl8GXxlYvQlC53KhegjzDwlUPS9ADUXo=";
  };

  qmkDefault = fetchurl {
    url = "https://github.com/j1n6/qmk-uconsole/releases/download/v${qmkVersion}/clockworkpi_uconsole_default.bin";
    hash = "sha256-KrgTg1Euo1t+xc7yPulGUAGTOCwH8U/Db9lpcfVGlOI=";
  };

  qmkNoTapHold = fetchurl {
    url = "https://github.com/j1n6/qmk-uconsole/releases/download/v${qmkVersion}/clockworkpi_uconsole_no_tap_hold.bin";
    hash = "sha256-NYIRloGy8pbqoseFctbj0vFe2Xo/qKpnHcfhIpMIlTw=";
  };

  # upload-reset built from the stock bundle's source, plus its stock firmware.
  stock = stdenv.mkDerivation {
    pname = "uconsole-keyboard-stock";
    version = "0-unstable-b953030";
    src = stockBundle;
    sourceRoot = "uconsole_keyboard_flash";
    buildPhase = ''
      runHook preBuild
      # Pre-C99 code (implicit-int main, bare `return;`): GCC 14 rejects it
      # unless built as gnu89.
      $CC -O2 -std=gnu89 -o upload-reset.bin upload-reset/upload-reset.c
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 upload-reset.bin $out/bin/upload-reset
      install -Dm644 uconsole_keyboard.ino.bin $out/share/uconsole-keyboard/stock.bin
      runHook postInstall
    '';
  };

  firmware = symlinkJoin {
    name = "uconsole-keyboard-firmware";
    paths = [ stock ];
    postBuild = ''
      ln -s ${qmkDefault} $out/share/uconsole-keyboard/qmk-${qmkVersion}-default.bin
      ln -s ${qmkNoTapHold} $out/share/uconsole-keyboard/qmk-${qmkVersion}-no-tap-hold.bin
    '';
  };
in
writeShellApplication {
  name = "uconsole-keyboard-flash";
  runtimeInputs = [
    dfu-util
    coreutils
  ];
  text = ''
    fw=${firmware}/share/uconsole-keyboard
    case "''${1:-}" in
      qmk) bin="$fw/qmk-${qmkVersion}-default.bin" ;;
      qmk-no-tap-hold) bin="$fw/qmk-${qmkVersion}-no-tap-hold.bin" ;;
      stock) bin="$fw/stock.bin" ;;
      "" | -h | --help)
        echo "usage: sudo uconsole-keyboard-flash qmk|qmk-no-tap-hold|stock|FILE.bin" >&2
        exit 64 ;;
      *) bin="$1" ;;
    esac
    [ -r "$bin" ] || { echo "no such firmware: $bin" >&2; exit 66; }
    [ "$(id -u)" = 0 ] || { echo "run as root (sudo)" >&2; exit 77; }

    # The stock firmware exposes a CDC-ACM serial port; find the one that
    # belongs to the keyboard (1eaf:0024) rather than assuming ttyACM0.
    port=""
    for t in /sys/class/tty/ttyACM*; do
      [ -e "$t" ] || continue
      d=$(readlink -f "$t/device/..")
      if [ "$(cat "$d/idVendor" 2>/dev/null)" = 1eaf ]; then
        port=/dev/$(basename "$t")
        break
      fi
    done

    if [ -n "$port" ]; then
      echo "Keyboard serial port $port found (stock-style firmware): resetting into the bootloader."
      # Upstream recommends 1500 ms rather than the bundle's 750 ms.
      ${stock}/bin/upload-reset "$port" 1500
      sleep 2
      ${stock}/bin/upload-reset "$port" 1500 || true
      dfu-util -d 1eaf:0003 -a 2 -D "$bin" -R
    else
      echo "No keyboard serial port (QMK firmware?). Waiting for the bootloader:"
      echo "press Left Alt + Right Alt + Start together now."
      dfu-util -w -d 1eaf:0003 -a 2 -D "$bin" -R
    fi
    echo "Done. If the keyboard is unresponsive, reboot and run again; see the package header for S1 recovery."
  '';
  meta = {
    description = "Flash the ClockworkPi uConsole keyboard (QMK v${qmkVersion} or stock)";
    platforms = lib.platforms.linux;
  };
}
