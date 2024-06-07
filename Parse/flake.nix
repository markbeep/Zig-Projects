{
  description = "My Flake";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = rec {
          default = Mez;
          Mez = pkgs.stdenv.mkDerivation {
            name = "Mez";
            src = ./.;

            buildInputs = [
              pkgs.zig
              pkgs.autoPatchelfHook
            ];
            dontConfigure = true;

            preBuild = ''
              # Necessary for zig cache to work
              export HOME=$TMPDIR
            '';

            installPhase = ''
              runHook preInstall
              zig build -Doptimize=ReleaseFast --prefix $out install
              runHook postInstall
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.zig
            pkgs.zls
            pkgs.gdb
          ];
        };
      }
    );
}
