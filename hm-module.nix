# Home Manager module for the MoErgo Glove80 keyboard.
#
# Declares `programs.glove80`, builds the ZMK firmware from the configured
# keymap + options, and installs a `glove80` flasher pre-pointed at that build.
#
# Self-contained: the firmware is built from `programs.glove80.source` (the
# MoErgo ZMK fork), so no extra flake inputs are required.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.glove80;
  ug = cfg.underglow;

  b = x: if x then "y" else "n";

  effects = {
    solid = 0;
    breathe = 1;
    spectrum = 2;
    swirl = 3;
    test = 4;
  };

  zmk = import cfg.source {
    pkgs = import "${cfg.source}/nix/pinned-nixpkgs.nix" {
      system = pkgs.stdenv.hostPlatform.system;
    };
  };

  kconfig = pkgs.writeText "glove80.conf" ''
    CONFIG_ZMK_RGB_UNDERGLOW=${b ug.enable}
    CONFIG_ZMK_RGB_UNDERGLOW_ON_START=${b ug.onStart}
    CONFIG_ZMK_RGB_UNDERGLOW_HUE_START=${toString ug.hue}
    CONFIG_ZMK_RGB_UNDERGLOW_SAT_START=${toString ug.saturation}
    CONFIG_ZMK_RGB_UNDERGLOW_BRT_START=${toString ug.brightness}
    CONFIG_ZMK_RGB_UNDERGLOW_BRT_MAX=${toString ug.brightnessMax}
    CONFIG_ZMK_RGB_UNDERGLOW_SPD_START=${toString ug.speed}
    CONFIG_ZMK_RGB_UNDERGLOW_EFF_START=${toString effects.${ug.effect}}
    CONFIG_ZMK_RGB_UNDERGLOW_AUTO_OFF_IDLE=${b ug.autoOffIdle}
    CONFIG_ZMK_RGB_UNDERGLOW_AUTO_OFF_USB=${b ug.autoOffUsb}

    CONFIG_ZMK_IDLE_TIMEOUT=${toString (cfg.idleTimeout * 1000)}
    CONFIG_ZMK_SLEEP=${b cfg.sleep.enable}
    ${lib.optionalString cfg.sleep.enable "CONFIG_ZMK_IDLE_SLEEP_TIMEOUT=${
      toString (cfg.sleep.timeout * 1000)
    }"}

    CONFIG_ZMK_BLE=${b cfg.bluetooth.enable}
    CONFIG_ZMK_USB=${b cfg.usb.enable}

    CONFIG_ZMK_KSCAN_DEBOUNCE_PRESS_MS=${toString cfg.debounce.pressMs}
    CONFIG_ZMK_KSCAN_DEBOUNCE_RELEASE_MS=${toString cfg.debounce.releaseMs}

    ${lib.optionalString cfg.usbLogging "CONFIG_ZMK_USB_LOGGING=y"}
    ${cfg.extraConfig}
  '';
in
{
  options.programs.glove80 = {
    enable = lib.mkEnableOption "Glove80 ZMK firmware (MoErgo fork)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { defaultFirmware = cfg.firmware; };
      defaultText = lib.literalExpression "the glove80 flasher pointed at the built firmware";
      description = ''
        The `glove80` flasher CLI to install. Defaults to the flasher with its
        built-in firmware set to {option}`programs.glove80.firmware`.
      '';
    };

    source = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchFromGitHub {
        owner = "moergo-sc";
        repo = "zmk";
        rev = "2f73a230e2fc7b2bd64a9736181e87bf54338131";
        hash = "sha256-WsQaX+g8XAmhTD9DjODzzw37Br1Wpd7wz34Rd9BvIvM=";
      };
      description = "MoErgo ZMK fork source tree (must contain nix/ build infrastructure).";
    };

    keymap = lib.mkOption {
      type = lib.types.coercedTo lib.types.lines (pkgs.writeText "glove80.keymap") lib.types.path;
      description = ''
        ZMK keymap (devicetree), as an inline string or a path to a .keymap
        file. Design it visually at https://my.glove80.com and paste the
        exported keymap here, or hand-edit. Renderable with keymap-drawer.
      '';
    };

    firmware = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      defaultText = lib.literalExpression "<derivation glove80.uf2>";
      description = ''
        The built combined (left + right) Glove80 UF2 firmware, derived from
        {option}`programs.glove80.keymap` and the other options. Read-only.
      '';
    };

    idleTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 2700;
      description = "Seconds of inactivity before RGB + BLE go idle.";
    };

    underglow = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Compile RGB underglow support into the firmware.";
      };
      onStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Turn the underglow on at boot.";
      };
      hue = lib.mkOption {
        type = lib.types.ints.between 0 359;
        default = 0;
        description = "Startup hue (degrees).";
      };
      saturation = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 100;
        description = "Startup saturation (percent).";
      };
      brightness = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 20;
        description = "Startup brightness (percent).";
      };
      brightnessMax = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 20;
        description = "Maximum brightness the underglow can reach (safety cap).";
      };
      speed = lib.mkOption {
        type = lib.types.ints.between 1 5;
        default = 3;
        description = "Startup animation speed (1–5).";
      };
      effect = lib.mkOption {
        type = lib.types.enum (builtins.attrNames effects);
        default = "solid";
        description = "Startup underglow effect.";
      };
      autoOffIdle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Turn the underglow off when the keyboard goes idle.";
      };
      autoOffUsb = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Turn the underglow off when USB is disconnected.";
      };
    };

    sleep = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow the keyboard to deep-sleep when idle.";
      };
      timeout = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1800;
        description = "Seconds of inactivity before deep sleep.";
      };
    };

    bluetooth.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Compile Bluetooth (BLE) support into the firmware.";
    };

    usb.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Compile wired USB HID support into the firmware.";
    };

    debounce = {
      pressMs = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 5;
        description = "Key-press debounce in milliseconds.";
      };
      releaseMs = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 5;
        description = "Key-release debounce in milliseconds.";
      };
    };

    usbLogging = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable USB serial logging (debug; central half only).";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra raw lines appended to the generated kconfig.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = ug.brightness <= ug.brightnessMax;
        message = "programs.glove80.underglow.brightness must be <= brightnessMax.";
      }
    ];

    programs.glove80.firmware =
      zmk.combine_uf2
        (zmk.zmk.override {
          board = "glove80_lh";
          inherit (cfg) keymap;
          inherit kconfig;
        })
        (zmk.zmk.override {
          board = "glove80_rh";
          inherit (cfg) keymap;
          inherit kconfig;
        })
        "glove80";

    home.packages = [ cfg.package ];
  };
}
