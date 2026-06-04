{
  description = "Nix package + Home Manager module for the MoErgo Glove80 keyboard";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      # Generic, firmware-agnostic flasher CLI.
      overlays.default = final: _prev: {
        glove80 = final.callPackage ./package.nix { };
      };

      packages = forAllSystems (system: rec {
        glove80 = (pkgsFor system).callPackage ./package.nix { };
        default = glove80;
      });

      # `programs.glove80`: builds firmware from your keymap + installs the
      # flasher pointed at it.
      homeManagerModules = rec {
        glove80 = ./hm-module.nix;
        default = glove80;
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShellNoCC {
          packages = [ (pkgsFor system).nixfmt-rfc-style ];
        };
      });
    };
}
