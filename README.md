# glove80-nix

Nix flake for the [MoErgo Glove80](https://www.moergo.com/) split keyboard:

- a **package** — `glove80`, a friendly USB flashing CLI (firmware-agnostic);
- a **Home Manager module** — `programs.glove80`, which builds ZMK firmware from
  your keymap and installs the flasher pointed at it.

## Home Manager — build firmware from your keymap

A minimal configuration only needs `enable` and a `keymap`; everything else has
sensible defaults. The full set of options (shown with their defaults) is:

```nix
{
  inputs.glove80-nix.url = "github:sand4rt/glove80-nix";
  # inputs.glove80-nix.inputs.nixpkgs.follows = "nixpkgs"; # optional

  # In your Home Manager configuration:
  imports = [ inputs.glove80-nix.homeManagerModules.default ];

  programs.glove80 = {
    enable = true;

    # Design at https://my.glove80.com, export, and paste here (or use a path).
    keymap = # devicetree
    ''
      // ... your ZMK devicetree keymap ...
    '';

    # MoErgo ZMK fork the firmware is built from. Override to pin a different
    # revision; must contain the `nix/` build infrastructure.
    # source = pkgs.fetchFromGitHub {
    #   owner = "moergo-sc";
    #   repo = "zmk";
    #   rev = "2f73a230e2fc7b2bd64a9736181e87bf54338131";
    #   hash = "sha256-WsQaX+g8XAmhTD9DjODzzw37Br1Wpd7wz34Rd9BvIvM=";
    # };

    idleTimeout = 2700; # seconds idle before RGB + BLE go idle

    underglow = {
      enable = true;       # compile RGB underglow support
      onStart = true;      # turn underglow on at boot
      hue = 0;             # 0–359 degrees
      saturation = 100;    # 0–100 percent
      brightness = 20;     # 0–100 percent (must be <= brightnessMax)
      brightnessMax = 20;  # 0–100 percent, safety cap
      speed = 3;           # 1–5 animation speed
      effect = "solid";    # solid | breathe | spectrum | swirl | test
      autoOffIdle = true;  # underglow off when keyboard goes idle
      autoOffUsb = false;  # underglow off when USB is disconnected
    };

    sleep = {
      enable = true;    # allow deep-sleep when idle
      timeout = 1800;   # seconds idle before deep sleep
    };

    bluetooth.enable = true; # compile BLE support
    usb.enable = true;       # compile wired USB HID support

    debounce = {
      pressMs = 5;    # key-press debounce (ms)
      releaseMs = 5;  # key-release debounce (ms)
    };

    usbLogging = false; # USB serial logging (debug; central half only)

    extraConfig = ""; # extra raw lines appended to the generated kconfig
  };
}
```

This installs a `glove80` command whose default firmware is your build, so
`glove80 flash` just works. The built UF2 is also exposed read-only at
`config.programs.glove80.firmware`.

## Flashing

With the Home Manager module the `glove80` command is already on your `PATH` and
defaults to your built firmware, so:

```sh
glove80 flash
```

Without installing anything, run it straight from the flake and point it at a
UF2:

```sh
nix run github:sand4rt/glove80-nix -- flash ./glove80.uf2
```

The CLI walks you through entering the bootloader on each half, then detects,
mounts, writes, and reboots them.

```
glove80 flash [FIRMWARE]   Flash firmware onto both halves over USB.
glove80 path  [FIRMWARE]   Print the resolved firmware (.uf2) path.
glove80 version            Print the version.
glove80 help               Show this help (default).
```

Firmware is resolved as: `FIRMWARE` argument → `$GLOVE80_FIRMWARE` → built-in
default (if the package was built with one).
