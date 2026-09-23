{
  description = "Darask Paint iopaint Linux runtime";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          source = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [ ./darask-plugin.sh ];
          };
          runtime = pkgs.writeShellApplication {
            name = "darask-paint-iopaint";
            runtimeInputs = with pkgs; [ python312 uv git curl cacert bash coreutils gnugrep findutils gnutar gzip util-linux gcc ];
            text = ''
              export DARASK_NIX_ENV=1
              export DARASK_PYTHON=${pkgs.python312}/bin/python3.12
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (with pkgs; [ stdenv.cc.cc.lib zlib glib libGL libxcb libX11 libXext libSM libICE ])}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              exec bash ${source}/darask-plugin.sh "$@"
            '';
          };
        in { default = runtime; });
      apps = forAllSystems (system: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/darask-paint-iopaint"; };
      });
      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          launcher = pkgs.runCommand "check-launcher" { nativeBuildInputs = [ pkgs.shellcheck pkgs.bash ]; } ''
            shellcheck ${./darask-plugin.sh}
            bash ${./darask-plugin.sh} --help
            touch $out
          '';
        });
    };
}
