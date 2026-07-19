{ ... }:
{
  imports = [
    ../../modules/nixos/profiles/cm4.nix
    ./disk-configuration.nix
  ];

  # Host-specific configuration for pi05 goes here.
  system.stateVersion = "24.11";
}
