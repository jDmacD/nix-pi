{
  perSystem =
    { pkgs, inputs', ... }:
    let
      # Builds the fleet's kernels (pi01 = Pi 4 and CM4 hosts, pi04 = Pi 5,
      # uconsole) with their module trees (kernel modules + zfs-kernel), all
      # in one `nix build` so they run side by side, and copies them to the
      # private S3 cache that picard substitutes from (blueprint's
      # jtec-nix-cache: Scaleway nl-ams, project `ephemeral`). cachix's free
      # tier evicts once full, so it's opt-in: CACHIX_PUSH=1. Credentials:
      # ~/.config/nix/jtec-nix-cache.aws and jtec-nix-cache-1.sec (blueprint
      # cloud-utils). NO_UPDATE=1 builds the committed flake.lock
      # instead of updating it first (do that for a lock you'll deploy).
      #
      #   build-ephemeral build-push
      build-push = pkgs.writeShellApplication {
        name = "build-push";
        runtimeInputs = [
          pkgs.cachix
          pkgs.omnix
        ];
        text = ''
          CACHE='s3://jtec-nix-cache?endpoint=s3.nl-ams.scw.cloud&region=nl-ams'
          SIGNING_KEY=''${SIGNING_KEY:-$HOME/.config/nix/jtec-nix-cache-1.sec}
          export AWS_SHARED_CREDENTIALS_FILE=''${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.config/nix/jtec-nix-cache.aws}

          if [ "''${NO_UPDATE:-0}" = 0 ]; then
            nix flake update --accept-flake-config
          fi
          # HOSTS: one per kernel (pi01 = Pi 4 + CM4, pi04 = Pi 5).
          attrs=()
          for h in ''${HOSTS:-pi01 pi04 uconsole}; do
            attrs+=(".#nixosConfigurations.$h.config.system.build.kernel"
                    ".#nixosConfigurations.$h.config.system.modulesTree")
          done
          # --keep-going: one kernel failing mustn't abort the others; push
          # whatever did build, then exit non-zero.
          status=0
          nix build "''${attrs[@]}" --keep-going --no-link --accept-flake-config || status=$?
          paths=()
          for a in "''${attrs[@]}"; do
            p=$(nix eval --raw --accept-flake-config "$a.outPath")
            if [ -e "$p" ]; then paths+=("$p"); else echo "build-push: not built: $a" >&2; fi
          done
          if [ ''${#paths[@]} -eq 0 ]; then
            echo "build-push: nothing built, nothing pushed" >&2
            exit 1
          fi
          nix copy --to "$CACHE&compression=zstd&secret-key=$SIGNING_KEY" "''${paths[@]}"
          if [ "''${CACHIX_PUSH:-0}" = 1 ]; then
            cachix push jdmacd "''${paths[@]}"
          fi
          printf '%s\n' "''${paths[@]}"
          exit "$status"
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
            # A temporary Hetzner CAX as the only aarch64 builder instead of
            # worf: `build-ephemeral build-push`. Boots blueprint's
            # role=arm-builder snapshot and deletes the server afterwards.
            inputs'.crann.packages.build-ephemeral
          ]
          ++ ([
            build-push
            deploy-staged
          ]);
      };
    };
}
