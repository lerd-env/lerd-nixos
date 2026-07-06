{
  description = "Lerd - Herd-like local PHP dev environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      packages = forAll (pkgs: rec {
        lerd = pkgs.callPackage ./package.nix { };
        default = lerd;
      });

      overlays.default = final: prev: {
        lerd = final.callPackage ./package.nix { };
      };
    };
}
