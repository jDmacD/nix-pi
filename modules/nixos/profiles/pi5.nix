# Shared module set for Raspberry Pi 5 hosts (NVMe via disko).
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
  ]
  ++ (with inputs.nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    sd-image
    usb-gadget-ethernet
  ]);

  # No raspberry-pi-5.page-size-16k. Despite the name it only overlays
  # jemalloc for 16K pages (the kernel's page size is unchanged), and that
  # re-hashes rustc and everything built with it, so worf compiled ~95 extra
  # derivations per update. Stock jemalloc (64K pages) runs fine on the 16K
  # kernel, and on these hosts only bind's `host` uses it. Envoy doesn't:
  # what Envoy needs is the VA_BITS_48 kernel patch in rpi-common.nix.

  # NVMe SSD firmware updates via LVFS (fwupdmgr refresh/get-updates/update).
  # Note: this does NOT update Pi bootloader/EEPROM firmware — that is handled
  # by nixos-raspberrypi. Only relevant here for the NVMe drive.
  services.fwupd.enable = true;
}
