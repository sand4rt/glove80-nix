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
        info ""
        info "Pass one explicitly:"
        info "    ''${bold}glove80 flash ./glove80.uf2''${rst}"
        info "or set ''${bold}\$GLOVE80_FIRMWARE''${rst}, or build with a default firmware."
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

    # Is the left half connected (normal or bootloader mode)?
    is_left_plugged_in() {
      grep -rqs "Glove80 LH" /sys/bus/usb/devices/*/product 2>/dev/null ||
        find_dev GLV80LHBOOT >/dev/null 2>&1
    }

    # Is the right half connected (normal or bootloader mode)?
    is_right_plugged_in() {
      grep -rqs "Glove80 RH" /sys/bus/usb/devices/*/product 2>/dev/null ||
        find_dev GLV80RHBOOT >/dev/null 2>&1
    }

    # $1 = label, $2 = side label, $3 = firmware path.
    # Returns 0 once that half has been flashed.
    flash_half() {
      local label="$1" side="$2" fw="$3" dev mnt out
      dev=$(find_dev "$label") || return 1

      info "  [$side] Detected at $dev"
      mnt=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -n1 || true)
      if [ -z "$mnt" ]; then
        info "  [$side] Mounting…"
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

      info "  [$side] Writing firmware…"
      if ! cp "$fw" "$mnt/"; then
        warn "  [$side] write error — retrying"
        return 1
      fi
      sync
      ok "  [$side] SUCCESS — flashed, rebooting."
      return 0
    }

    # Flash one half sequentially, showing side-specific bootloader instructions.
    # $1 = boot label, $2 = side (LEFT|RIGHT), $3 = display name,
    # $4 = combo text, $5 = firmware path.
    flash_side() {
      local label="$1" side="$2" display="$3" combo="$4" fw="$5"

      if ! find_dev "$label" >/dev/null 2>&1; then
        if [ "$side" = "LEFT" ]; then
          if ! is_left_plugged_in; then
            step "Plug in the $display half via USB."
            while ! is_left_plugged_in; do sleep 0.5; done
          fi
        else
          if ! is_right_plugged_in; then
            step "Plug in the $display half via USB."
            while ! is_right_plugged_in; do sleep 0.5; done
          fi
        fi
        ok "  $display keyboard detected."
        info ""
        info "Hold ''${bold}$combo''${rst} to enter bootloader."
        info ""
        while ! find_dev "$label" >/dev/null 2>&1; do sleep 0.5; done
      else
        ok "  $display keyboard detected."
        info ""
      fi

      while ! flash_half "$label" "$side" "$fw"; do sleep 0.5; done
    }

    # ------------------------------------------------------------- commands --
    cmd_flash() {
      local fw
      fw=$(resolve_firmware "''${1:-}") || return 1

      info "''${bold}Glove80 Firmware Flash''${rst}"
      info "''${dim}firmware: $fw''${rst}"
      info ""

      if ! is_plugged_in; then
        step "Plug in one or both halves via USB."
        while ! is_plugged_in; do sleep 0.5; done
        info ""
      fi

      flash_side GLV80LHBOOT LEFT "Left" \
        "Magic key (bottom-left) + the E key" "$fw"
      info ""
      flash_side GLV80RHBOOT RIGHT "Right" \
        "PgDn key (bottom-right) + the I key" "$fw"
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
      Run ''${bold}glove80 flash''${rst}, plug in each half via USB, then put it into
      bootloader using the key combo for that half:

        LEFT  half: hold ''${bold}Magic key (bottom-left)''${rst} + the ''${bold}E key''${rst}
        RIGHT half: hold ''${bold}PgDn key (bottom-right)''${rst} + the ''${bold}I key''${rst}

      Each half is detected, mounted, flashed, and reboots itself.
      One cable is fine — do the halves one at a time. Ctrl-C to abort.
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
