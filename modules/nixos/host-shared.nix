{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{

  imports = [
  ];

  # Shared Nix configuration
  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      # Runtime caches for the Pis themselves (used when a host rebuilds/pulls
      # packages). extra-* appends to the defaults (cache.nixos.org) and to
      # anything nixos-raspberrypi already configures, rather than clobbering it.
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
      # Safety net: if free space drops below min-free while copying/building
      # (e.g. a deploy), Nix collects garbage until max-free is available. The
      # tpi hosts' /nix is only a 32 GB partition.
      min-free = 2 * 1024 * 1024 * 1024;
      max-free = 8 * 1024 * 1024 * 1024;
    };

    # Weekly GC. Generations are pruned by count, not age: fleet updates are
    # infrequent, so `--delete-older-than` would delete the only rollback
    # generation on the first run after an upgrade. Keep the last 3 system
    # generations (the bootloader only lists 2 anyway), then collect
    # unreferenced store paths. The random delay keeps the hosts from all
    # collecting at once (and loading Ceph's disks together).
    gc = {
      automatic = true;
      dates = "weekly";
      randomizedDelaySec = "6h";
      options = "";
    };

    extraOptions = ''
      # Ensure we can still build when missing-server is not accessible
      fallback = true
    '';
  };

  systemd.services.nix-gc.preStart = ''
    ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +3
  '';

  time.timeZone = lib.mkDefault "Europe/Dublin";

  # Compressed RAM swap: gives memory-constrained Pis headroom under pressure
  # without wearing the SD card or paging to slow storage.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
  };
}
