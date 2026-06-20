# Standalone, firmware-agnostic flashing helper for the MoErgo Glove80
# keyboard. This derivation has no dependency on any particular keymap or
# firmware build, so it is suitable for upstreaming to nixpkgs as `glove80`.
#
# The firmware to flash is resolved at runtime, in order of precedence:
#   1. the path passed on the command line   (`glove80 flash ./my.uf2`)
#   2. the $GLOVE80_FIRMWARE environment variable
#   3. the `defaultFirmware` baked in at build time (may be null)
{
  lib,
  writeShellApplication,
  coreutils,
  util-linux,
  udisks2,
  gnugrep,
  findutils,
  # Optional UF2 baked in as the default firmware. When null, a firmware
  # path must be supplied at runtime (argument or $GLOVE80_FIRMWARE).
  defaultFirmware ? null,
  version ? "0-unstable",
}:
writeShellApplication {
  name = "glove80";

  runtimeInputs = [
    coreutils
    util-linux
    udisks2
    gnugrep
    findutils
  ];

  text = ''
    VERSION=${lib.escapeShellArg version}
    DEFAULT_FIRMWARE=${
      lib.escapeShellArg (if defaultFirmware == null then "" else "${defaultFirmware}/glove80.uf2")
    }

    # ---------------------------------------------------------------- output --
    if [ -t 2 ]; then
      bold=$'\e[1m'; dim=$'\e[2m'; red=$'\e[31m'; grn=$'\e[32m'
      ylw=$'\e[33m'; cyn=$'\e[36m'; rst=$'\e[0m'
    else
      bold=""; dim=""; red=""; grn=""; ylw=""; cyn=""; rst=""
    fi
    apos="'"

    info()  { printf '%s\n' "$*"; }
    step()  { printf '%s» %s%s\n' "$cyn" "$*" "$rst"; }
    ok()    { printf '%s✓ %s%s\n' "$grn" "$*" "$rst"; }
    warn()  { printf '%s! %s%s\n' "$ylw" "$*" "$rst" >&2; }
    err()   { printf '%s✗ %s%s\n' "$red" "$*" "$rst" >&2; }

    # -------------------------------------------------------------- firmware --
    # Resolve which UF2 to flash. Optional first argument overrides everything.
    resolve_firmware() {
      local fw="''${1:-''${GLOVE80_FIRMWARE:-$DEFAULT_FIRMWARE}}"

      if [ -z "$fw" ]; then
        err "No firmware specified."
        info "" >&2
        info "Pass one explicitly:" >&2
        info "    ''${bold}glove80 flash ./glove80.uf2''${rst}" >&2
        info "or set ''${bold}\$GLOVE80_FIRMWARE''${rst}, or build with a default firmware." >&2
        return 1
      fi
      if [ ! -f "$fw" ]; then
        err "Firmware not found: $fw"
        return 1
      fi
      printf '%s' "$fw"
    }

    # ------------------------------------------------------------ device i/o --
    # $1 = filesystem label -> prints /dev path, or fails.
    find_dev() {
      local want="$1" path label
      while read -r path label; do
        [ "$label" = "$want" ] && { printf '%s' "$path"; return 0; }
      done < <(lsblk -o PATH,LABEL -nr)
      return 1
    }

    # Is any Glove80 half connected (normal or bootloader mode)?
    is_plugged_in() {
      grep -rqs "Glove80" /sys/bus/usb/devices/*/product 2>/dev/null ||
        find_dev GLV80LHBOOT >/dev/null 2>&1 ||
        find_dev GLV80RHBOOT >/dev/null 2>&1
    }

    # $1 = label, $2 = side label, $3 = firmware path.
    # Returns 0 once that half has been flashed.
    flash_half() {
      local label="$1" side="$2" fw="$3" dev mnt out
      dev=$(find_dev "$label") || return 1

      info "  [$side] detected at $dev"
      mnt=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -n1 || true)
      if [ -z "$mnt" ]; then
        info "  [$side] mounting…"
        if ! out=$(udisksctl mount -b "$dev" 2>/dev/null); then
          warn "  [$side] could not mount — retrying"
          return 1
        fi
        mnt=''${out##* at }
        mnt=''${mnt%.}
      fi
      if [ -z "$mnt" ] || [ ! -d "$mnt" ]; then
        warn "  [$side] no mount point — retrying"
        return 1
      fi

      info "  [$side] writing firmware…"
      if ! cp "$fw" "$mnt/"; then
        warn "  [$side] write error — retrying"
        return 1
      fi
      sync
      ok "  [$side] flashed — rebooting."
      return 0
    }

    # ------------------------------------------------------------- commands --
    cmd_flash() {
      local fw
      fw=$(resolve_firmware "''${1:-}") || return 1

      info "''${dim}firmware: $fw''${rst}"
      info ""

      if ! is_plugged_in; then
        step "Plug in one or both halves via USB."
        while ! is_plugged_in; do sleep 0.5; done
        ok "Keyboard detected."
        info ""
      fi

      local lh=0 rh=0 prompted=0
      find_dev GLV80LHBOOT >/dev/null 2>&1 && lh=2
      find_dev GLV80RHBOOT >/dev/null 2>&1 && rh=2

      if [ "$lh" = 2 ] && [ "$rh" = 2 ]; then
        step "Both halves in bootloader. Flashing…"
      elif [ "$lh" = 2 ]; then
        step "LEFT half in bootloader — flashing it now."
        info "  Put the RIGHT half into bootloader when ready:"
        info "    ''${bold}Power-up (recommended):''${rst} power off → hold ''${bold}I + PgDn''${rst} → power on"
        info "    ''${bold}ZMK shortcut (quicker):''${rst}  ''${bold}Magic + ''${apos}''${rst}"
        info "  Slow-pulsing red LED = bootloader ready."
      elif [ "$rh" = 2 ]; then
        step "RIGHT half in bootloader — flashing it now."
        info "  Put the LEFT half into bootloader when ready:"
        info "    ''${bold}Power-up (recommended):''${rst} power off → hold ''${bold}Magic + E''${rst} → power on"
        info "    ''${bold}ZMK shortcut (quicker):''${rst}  ''${bold}Magic + Esc''${rst}"
        info "  Slow-pulsing red LED = bootloader ready."
      else
        step "Put the plugged-in half into bootloader mode."
        info "    ''${bold}Power-up (recommended)''${rst} — power off, then hold while powering on:"
        info "      Left:  ''${bold}Magic + E''${rst}    Right: ''${bold}I + PgDn''${rst}"
        info "    ''${bold}ZMK shortcut (quicker)''${rst}:"
        info "      Left:  ''${bold}Magic + Esc''${rst}  Right: ''${bold}Magic + ''${apos}''${rst}"
        info "  Slow-pulsing red LED = bootloader ready.  ''${dim}Ctrl-C to abort.''${rst}"
      fi
      info ""

      lh=0
      rh=0
      while [ "$lh" = 0 ] || [ "$rh" = 0 ]; do
        if [ "$lh" = 0 ] && flash_half GLV80LHBOOT LEFT "$fw"; then lh=1; fi
        if [ "$rh" = 0 ] && flash_half GLV80RHBOOT RIGHT "$fw"; then rh=1; fi

        if [ "$lh" = 1 ] && [ "$rh" = 0 ] && [ "$prompted" != "r" ]; then
          info ""
          step "LEFT flashed. Plug in the RIGHT half (or swap cable) and enter bootloader:"
          info "    ''${bold}Power-up (recommended):''${rst} power off → hold ''${bold}I + PgDn''${rst} → power on"
          info "    ''${bold}ZMK shortcut (quicker):''${rst}  ''${bold}Magic + ''${apos}''${rst}"
          info "  Slow-pulsing red LED = bootloader ready."
          prompted=r
        elif [ "$rh" = 1 ] && [ "$lh" = 0 ] && [ "$prompted" != "l" ]; then
          info ""
          step "RIGHT flashed. Plug in the LEFT half (or swap cable) and enter bootloader:"
          info "    ''${bold}Power-up (recommended):''${rst} power off → hold ''${bold}Magic + E''${rst} → power on"
          info "    ''${bold}ZMK shortcut (quicker):''${rst}  ''${bold}Magic + Esc''${rst}"
          info "  Slow-pulsing red LED = bootloader ready."
          prompted=l
        fi

        if [ "$lh" = 0 ] || [ "$rh" = 0 ]; then sleep 0.5; fi
      done

      info ""
      ok "Done. Both halves flashed."
    }

    cmd_path() {
      local fw
      fw=$(resolve_firmware "''${1:-}") || return 1
      printf '%s\n' "$fw"
    }

    cmd_version() { printf 'glove80 %s\n' "$VERSION"; }

    cmd_help() {
      cat <<EOF
    ''${bold}glove80''${rst} — build/flash helper for the MoErgo Glove80 keyboard

    ''${bold}Usage:''${rst}
      glove80 flash [FIRMWARE]   Flash firmware onto both halves over USB.
      glove80 path  [FIRMWARE]   Print the resolved firmware (.uf2) path.
      glove80 version            Print the version.
      glove80 help               Show this help (default).

    ''${bold}Firmware resolution''${rst} (highest precedence first):
      1. FIRMWARE argument          e.g. glove80 flash ./glove80.uf2
      2. \$GLOVE80_FIRMWARE          environment variable
      3. built-in default           baked in at build time

    ''${bold}Flashing''${rst}:
      Run ''${bold}glove80 flash''${rst}, then plug in each half via USB and enter bootloader
      mode (look for a slow-pulsing red LED next to the power switch):

        Power-up method (recommended — power off, hold keys, then power on):
          Left:  Magic + E      Right: I + PgDn
        ZMK method (quicker, less reliable):
          Left:  Magic + Esc    Right: Magic + ''${apos}

      Each half is detected, mounted, flashed, and reboots. One cable is fine;
      do halves one at a time, or both at once with two cables. Ctrl-C to abort.
    EOF
    }

    # ---------------------------------------------------------------- main --
    case "''${1:-help}" in
      flash)            shift; cmd_flash "$@" ;;
      path)             shift; cmd_path "$@" ;;
      version | -V | --version) cmd_version ;;
      help | -h | --help)       cmd_help ;;
      *)
        err "unknown command: ''${1}"
        info ""
        cmd_help >&2
        exit 1
        ;;
    esac
  '';
}
