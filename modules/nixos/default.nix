{ lib, ... }:
{
  imports = [
    ./rpi-common.nix
  ];
  system.stateVersion = lib.mkDefault "25.05";
}
