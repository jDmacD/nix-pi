# Shared module set for Raspberry Pi 4 hosts.
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
  ]
  ++ (with inputs.nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
    sd-image
    usb-gadget-ethernet
  ]);
}
