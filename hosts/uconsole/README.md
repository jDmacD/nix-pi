# uConsole

NixOS configuration for the [ClockworkPi uConsole](https://www.clockworkpi.com/uconsole)
— a handheld Linux terminal built around a Raspberry Pi Compute Module 4 (CM4).

## How it's built

Hardware support comes from the
[nixos-uconsole](https://github.com/nixos-uconsole/nixos-uconsole) flake
(`inputs.nixos-uconsole`), which provides the uConsole kernel, `config.txt`, and
CM modules **layered on the stock `nvmd/nixos-raspberrypi`** — no fork, so it
coexists with the rest of the fleet's `nixos-raspberrypi` cleanly.

The host is built in `hosts/default.nix` with:

```nix
uconsole = inputs.nixos-uconsole.lib.mkUConsoleSystem {
  variant = "cm4";
  specialArgs = { inherit inputs; };   # so users/locale/sops resolve inputs.sops-nix
  modules = [ ./uconsole/configuration.nix ];
};
```

`mkUConsoleSystem` wraps `nixos-raspberrypi.lib.nixosSystem` and imports the
uConsole hardware modules plus an upstream `base` module that owns the system
baseline (kernel, boot loader, filesystems, console font, NetworkManager, SSH,
and a batteries-included package set).

nixpkgs note: `nixos-uconsole` is left on its own pinned inputs (nixpkgs 25.11 +
a specific `nixos-raspberrypi` tag) rather than following nix-pi's unstable. That
pin is a matched pair — feeding the tagged `nixos-raspberrypi` an unstable
nixpkgs breaks the RPi platform (`stdenv.hostPlatform.linux-kernel` goes missing
and the "kernel" bootloader fails to evaluate). So the uConsole runs 25.11 (and
gets upstream's Cachix kernel cache) while the fleet stays on unstable.

## Not a cluster node

The uConsole is a personal handheld, not a k3s member, so it does **not** use the
`mkHost` helper and never imports `modules/nixos` (the k3s/rpi-common
aggregator). Its `configuration.nix` cherry-picks only the shared modules it
wants — `users` (accounts + SSH keys), `locale`, `sops` — and inherits the rest
from `mkUConsoleSystem`'s `base`. Because that upstream `base` enables password
and root SSH, `configuration.nix` re-asserts nix-pi's key-only, no-root policy
with `lib.mkForce`.

## Building the SD image

```
nix build .#uconsole-sdImage
```

(aarch64 — build on an aarch64 machine, a remote builder, or with binfmt
emulation, same as the other hosts.)

## Deploying

It's a normal deploy-rs node reachable over its USB-gadget / LAN port:

```
deploy .#uconsole
```

## Notes

- `rtl8812au` out-of-tree module for the external USB Wi-Fi dongle;
  `wirelesstools` / `iw` for connectivity.
- Serial getty on `ttyS0` is disabled (no serial console on this board).
- Home-manager is intentionally **not** wired up here.
