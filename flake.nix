{
    description = "My Flake";
    inputs = {
        flake-utils.url = "github:numtide/flake-utils";
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
        zls.url = "github:zigtools/zls/master";
    };

    outputs = { self, nixpkgs, flake-utils, zls }:
        flake-utils.lib.eachDefaultSystem (system:
            let
                pkgs = import nixpkgs { inherit system; };
                zig = pkgs.stdenv.mkDerivation rec {
                    name = "zig";
                    version = "0.12.0-dev.1879+e19219fa0";

                    src = fetchTarball {
                        url = "https://ziglang.org/builds/zig-linux-x86_64-${version}.tar.xz";
                        sha256 = "sha256:1wmmzqqwkq32rjb2crabwz8jdp9kb2fx9walvafcj2x626xvc0gh";
                    };

                    buildInputs = [];

                    installPhase = ''
                        mkdir -p $out/bin
                        cp -r $src/zig $src/lib $out/bin
                    '';
                };
                zls-pkg = zls.packages.${system}.zls;
            in
            {
                devShells.default = pkgs.mkShell {
                    buildInputs = [ 
                        zig
                        zls-pkg
                    ];
                };
            }
    );
}
