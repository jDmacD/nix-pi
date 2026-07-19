{ lib, ... }:
{
  imports = [
    ./rpi-common.nix
    ./host-shared.nix
    ./locale.nix
    ./ssh.nix
    ./sops.nix
    ./k3s.nix
    ./users.nix
  ];
  system.stateVersion = lib.mkDefault "25.05";
}
