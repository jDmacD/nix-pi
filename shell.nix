{
  perSystem =
    { pkgs, inputs', ... }:
    let
      build-push = pkgs.writeShellApplication {
        name = "build-push";
        runtimeInputs = [
          pkgs.cachix
          pkgs.omnix
        ];
        text = ''
          nix flake update --accept-flake-config
          nix build .#nixosConfigurations.pi01.config.boot.kernelPackages.kernel \
            --no-link --print-out-paths --accept-flake-config \
            | xargs cachix push jdmacd
          nix build .#nixosConfigurations.pi04.config.boot.kernelPackages.kernel \
            --no-link --print-out-paths --accept-flake-config \
            | xargs cachix push jdmacd
          nix build .#nixosConfigurations.tpi01.config.boot.kernelPackages.kernel \
            --no-link --print-out-paths --accept-flake-config \
            | xargs cachix push jdmacd
          nix build .#nixosConfigurations.uconsole.config.boot.kernelPackages.kernel \
            --no-link --print-out-paths --accept-flake-config \
            | xargs cachix push jdmacd
        '';
      };

      deploy-staged = pkgs.writeShellApplication {
        name = "deploy-staged";
        runtimeInputs = [
          inputs'.deploy-rs.packages.default
        ];
        text = ''
          deploy --targets .#pi01 .#pi02 .#pi03
          deploy --skip-checks --targets .#pi04 .#pi05
          deploy --skip-checks --targets .#tpi04 .#tpi03 .#tpi02 .#tpi01
        '';
      };
    in
    {
      devShells.default = pkgs.mkShell {
        name = "nix-pi";
        packages =
          with pkgs;
          [
            # fleet deployment (see deploy.nix)
            inputs'.deploy-rs.packages.default
            # secrets management (see modules/nixos/sops.nix, .sops.yaml)
            sops
            age
            ssh-to-age
            # disk layout for Pi 5 / CM4 hosts
            disko
            # nix tooling
            nixfmt
            nix-tree
            omnix
            cachix
          ]
          ++ ([ build-push ]);
      };
    };
}
