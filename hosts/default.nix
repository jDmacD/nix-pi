{ inputs, lib, ... }:
let
  # Build a Raspberry Pi host from its per-host module. The shared modules, the
  # `nixos-raspberrypi` overlays/module-arg (via lib.nixosSystem) and the
  # hostname (derived from the attribute name) are wired in here, so each host
  # file only carries what is unique to that machine.
  mkHost =
    name:
    inputs.nixos-raspberrypi.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ../modules/nixos
        { networking.hostName = name; }
        (./. + "/${name}/configuration.nix")
      ];
    };

  # The ClockworkPi uConsole (CM4) is not a cluster node, so it does not go
  # through `mkHost` (which imports the k3s/rpi aggregator). It is built with
  # nixos-uconsole's `mkUConsoleSystem`, which wraps `nixos-raspberrypi.lib`
  # and layers in the uConsole kernel/config.txt/hardware modules. We thread
  # nix-pi's `inputs` through `specialArgs` so the shared modules the host
  # imports (users/locale/sops) still resolve `inputs.sops-nix`.
  uconsole = inputs.nixos-uconsole.lib.mkUConsoleSystem {
    variant = "cm4";
    specialArgs = { inherit inputs; };
    modules = [ ./uconsole/configuration.nix ];
  };

  nixosConfigurations = {
    pi01 = mkHost "pi01";
    pi02 = mkHost "pi02";
    pi03 = mkHost "pi03";
    pi04 = mkHost "pi04";
    pi05 = mkHost "pi05";
    tpi01 = mkHost "tpi01";
    tpi02 = mkHost "tpi02";
    tpi03 = mkHost "tpi03";
    tpi04 = mkHost "tpi04";
    inherit uconsole;
  };
in
{
  flake.nixosConfigurations = nixosConfigurations;

  # Expose each host's SD image as a package, e.g. `nix build .#pi04-sdImage`.
  # The images are aarch64 builds, so they only appear under the aarch64-linux
  # package set — build them on an aarch64 machine, a remote builder, or via
  # binfmt emulation on x86_64.
  perSystem =
    { system, ... }:
    lib.optionalAttrs (system == "aarch64-linux") {
      packages = lib.mapAttrs' (
        name: cfg: lib.nameValuePair "${name}-sdImage" cfg.config.system.build.sdImage
      ) nixosConfigurations;
    };
}
