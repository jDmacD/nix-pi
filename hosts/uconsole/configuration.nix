{
  lib,
  pkgs,
  config,
  nixos-raspberrypi,
  ...
}:
{
  # nixos-uconsole's `base`/`kernel`/`configtxt`/`cm` modules (added by
  # mkUConsoleSystem in hosts/default.nix) own the hardware baseline: kernel,
  # config.txt, boot loader, filesystems, console font, NetworkManager and a
  # batteries-included package set. We only layer on the nix-pi bits that don't
  # conflict with that baseline. Notably we do NOT import the whole
  # modules/nixos aggregator (that pulls in k3s + rpi-common, neither of which
  # this handheld wants) — this is why the uConsole skips `mkHost`.
  imports = [
    ../../modules/nixos/users.nix
    ../../modules/nixos/locale.nix
    ../../modules/nixos/sops.nix
    # SD image + USB-gadget networking come from the same nixos-raspberrypi that
    # mkUConsoleSystem builds against (passed in as the `nixos-raspberrypi`
    # arg), so they match the uConsole kernel/firmware.
    nixos-raspberrypi.nixosModules.sd-image
    nixos-raspberrypi.nixosModules.usb-gadget-ethernet
  ];

  networking.hostName = "uconsole";
  networking.networkmanager.enable = true;

  # nix-pi's ssh policy: key-only, no root login. Upstream's `base` enables
  # openssh with password + root login, so force ours over it.
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    PermitRootLogin = lib.mkForce "no";
  };

  # Out-of-tree driver for the external RTL8812AU USB Wi-Fi dongle.
  boot.extraModulePackages = with config.boot.kernelPackages; [ rtl8812au ];

  environment.systemPackages = with pkgs; [
    wirelesstools
    iw
    git
  ];

  # No serial console on this board.
  systemd.services."serial-getty@ttyS0".enable = false;

  # nixos-uconsole's base does not set a stateVersion; match the fleet default.
  system.stateVersion = "25.05";
}
