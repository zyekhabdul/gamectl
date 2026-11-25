{
  description = "Sovereign TUI Game Manager & Launcher for Linux (Zero-Bloat)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        runtimeDeps = with pkgs; [
          bash
          curl
          file
          fzf
          jq
          openssh
          python3
          rsync
          unzip
          zip
        ];
        depotDl = pkgs.rustPlatform.buildRustPackage {
          pname = "gamectl-depot-dl";
          version = "0.1.2";

          src = pkgs.lib.cleanSourceWith {
            src = ./crates/depot-dl;
            filter = path: type:
              (baseNameOf path != "target") && (pkgs.lib.cleanSourceFilter path type);
          };

          cargoLock = {
            lockFile = ./crates/depot-dl/Cargo.lock;
          };

          cargoBuildFlags = [ "--bin" "gamectl-depot-dl" ];

          meta = with pkgs.lib; {
            description = "Native Rust Steam CDN depot downloader for gamectl";
            homepage = "https://github.com/zyekhabdul/gamectl";
            license = licenses.gpl2Only;
            platforms = platforms.linux;
            mainProgram = "gamectl-depot-dl";
          };
        };
        gamectl = pkgs.stdenv.mkDerivation {
          pname = "gamectl";
          version = "1.4.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin $out/share/bash-completion/completions $out/share/applications $out/share/doc/gamectl $out/share/licenses/gamectl
            cp bin/gamectl $out/bin/gamectl
            chmod +x $out/bin/gamectl
            ln -sf ${depotDl}/bin/gamectl-depot-dl $out/bin/gamectl-depot-dl
            wrapProgram $out/bin/gamectl \
              --prefix PATH : "$out/bin:${pkgs.lib.makeBinPath runtimeDeps}"
            ln -sf gamectl $out/bin/game

            cp completions/gamectl.bash $out/share/bash-completion/completions/gamectl
            ln -sf gamectl $out/share/bash-completion/completions/game

            cp gamectl.desktop $out/share/applications/gamectl.desktop
            cp README.md $out/share/doc/gamectl/
            cp LICENSE $out/share/licenses/gamectl/LICENSE
          '';

          meta = with pkgs.lib; {
            description = "Sovereign TUI Game Manager & Launcher for Linux (Zero-Bloat)";
            homepage = "https://github.com/zyekhabdul/gamectl";
            license = [ licenses.mit licenses.gpl2Only ];
            platforms = platforms.linux;
            mainProgram = "gamectl";
          };
        };
      in
      {
        packages = {
          default = gamectl;
          inherit gamectl;
          depot-dl = depotDl;
        };

        apps = {
          default = flake-utils.lib.mkApp {
            drv = gamectl;
          };
          depot-dl = flake-utils.lib.mkApp {
            drv = depotDl;
          };
        };
      }
    );
}
