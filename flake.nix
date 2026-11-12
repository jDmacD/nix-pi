{
  description = "Description for the project";

  # Build-time caches used when evaluating/building this flake (e.g. SD images)
  # on the build host. Runtime caches for the Pis themselves live in
  # modules/nixos/host-shared.nix. Requires --accept-flake-config (or these
  # substituters being trusted) to take effect.
  nixConfig = {
    extra-substituters = [
      "https://jdmacd.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      # Upstream uConsole cache (its 25.11 kernels; nix-pi's uConsole now builds
      # its own 6.12.87 kernel). See hosts/uconsole.
      "https://nixos-clockworkpi-uconsole.cachix.org"
    ];
    extra-trusted-public-keys = [
      "jdmacd.cachix.org-1:0DcSfXShBIng2EbPW44fxoXjXowKhZZWrbYqcozFhfM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "nixos-clockworkpi-uconsole.cachix.org-1:6NRN3n9/r3w5ZS8/gZudW6PkPDoC3liCt/dBseICua0="
    ];
  };

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    disko.url = "github:nix-community/disko";
    sops-nix.url = "github:Mic92/sops-nix";

    # Shared modules (k3s). crann's k3s module pins the k3s package through its
    # own nixpkgs-multiverse input, so following our nixpkgs doesn't move k3s.
    crann = {
      url = "github:jDmacD/crann";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # uConsole-only: ClockworkPi uConsole (CM4) hardware modules, layered on the
    # stock nixos-raspberrypi (no fork). Upstream pins nixpkgs 25.11 (EOL) plus
    # the nixos-raspberrypi tag v1.20260317.0; we override both so the uConsole
    # runs nixos-unstable (26.11pre), the same nixpkgs crann's niri/noctalia
    # follow. It gets its own nixos-raspberrypi input so the fleet's pin (and
    # its 26.05 nixpkgs) never moves with it. The old tag broke on unstable
    # (`stdenv.hostPlatform.linux-kernel` missing); nixos-raspberrypi `main`
    # evaluates fine. See hosts/uconsole/README.md.
    nixos-raspberrypi-uconsole = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-uconsole = {
      url = "github:nixos-uconsole/nixos-uconsole";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-raspberrypi.follows = "nixos-raspberrypi-uconsole";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import an internal flake module: ./other.nix
        # To import an external flake module:
        #   1. Add foo to inputs
        #   2. Add foo as a parameter to the outputs function
        #   3. Add here: foo.flakeModule
        ./hosts
        ./shell.nix
        ./deploy.nix

      ];
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.
          formatter = pkgs.nixfmt-tree;

        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
