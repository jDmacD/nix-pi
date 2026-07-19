{
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
    };

    extraOptions = ''
      # Ensure we can still build when missing-server is not accessible
      fallback = true
    '';
  };

  time.timeZone = lib.mkDefault "Europe/Dublin";

  # Compressed RAM swap: gives memory-constrained Pis headroom under pressure
  # without wearing the SD card or paging to slow storage.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
  };
}
