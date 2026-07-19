# Shared module set for Raspberry Pi 5 hosts (NVMe via disko).
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
  ]
  ++ (with inputs.nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    sd-image
    usb-gadget-ethernet
  ]);
}
