{
  description = "Sovereign TUI Game Manager & Launcher for Linux (Zero-Bloat)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "gamectl";
          version = "1.2.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -p $out/bin $out/share/bash-completion/completions $out/share/applications $out/share/doc/gamectl $out/share/licenses/gamectl
            cp bin/gamectl $out/bin/gamectl
            chmod +x $out/bin/gamectl
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
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "gamectl";
          };
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };
      }
    );
}
