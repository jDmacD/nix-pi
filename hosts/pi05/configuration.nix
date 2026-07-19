{ ... }:
{
  imports = [
    ../../modules/nixos/profiles/pi5.nix
    ./disk-configuration.nix
  ];

  # Host-specific configuration for pi05 goes here.
}
