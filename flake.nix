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
      # Prebuilt uConsole kernel/packages (25.11); see hosts/uconsole.
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

    # uConsole-only: ClockworkPi uConsole (CM4) hardware modules, layered on the
    # stock nixos-raspberrypi (no fork). Deliberately NOT following our unstable
    # nixpkgs: upstream pins nixpkgs to 25.11 alongside a specific
    # nixos-raspberrypi tag, and feeding that tag unstable breaks the RPi
    # platform (`stdenv.hostPlatform.linux-kernel` goes missing → the "kernel"
    # bootloader fails to evaluate). So the uConsole tracks 25.11 while the rest
    # of the fleet stays on unstable.
    nixos-uconsole.url = "github:nixos-uconsole/nixos-uconsole";

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
