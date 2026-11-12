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

nixpkgs note: nix-pi overrides upstream's pins (nixpkgs 25.11, which is EOL,
and `nixos-raspberrypi` tag `v1.20260317.0`). The uConsole follows nix-pi's own
`nixpkgs` (`nixos-unstable`, 26.11pre), the same nixpkgs crann and its niri /
noctalia follow, and gets a dedicated `nixos-raspberrypi-uconsole` input on
`main` so the fleet's `nixos-raspberrypi` pin (and its 26.05 nixpkgs) never moves
with it. The old tag broke on unstable (`stdenv.hostPlatform.linux-kernel`
missing); `main` is fine.

Kernel: pinned to **6.12.87** with its matching firmware bundle
(`pkgs.linuxAndFirmware.v6_12_87`) instead of nixos-raspberrypi's default 6.18.x.
All of nixos-uconsole's kernel patches apply cleanly to 6.12.87. On 6.18,
`0003-power` (battery reporting in `axp20x_battery.c`) and `0007` need a rebase,
and upstream reported a CM4 boot break when it moved nixos-raspberrypi forward.
No cache carries this patched kernel: the first build compiles it on worf
(~3 h). Push the result to Cachix to avoid repeating that.

Since 26.11 removed the scripted initrd, the uConsole boots a systemd initrd
(as the fleet Pis already do).

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

It's a normal deploy-rs node at `uconsole.lan` over Wi-Fi (Kea reservation
`192.168.178.99` plus an Unbound override on OPNsense). There is no USB
networking: the USB-C port is power-only and the CM4's USB controller runs in
host mode for the internal hub.

```
deploy .#uconsole
```

## Notes

- No `rtl8812au` module (it forced a kernel rebuild; on 26.05 the in-tree
  `rtw88_8812au` driver covers the USB Wi-Fi dongle);
  `wirelesstools` / `iw` for connectivity.
- Serial getty on `ttyS0` is disabled (no serial console on this board).
- Desktop (`desktop.nix`, `home.nix`): crann's niri + noctalia, started by
  greetd/tuigreet (no GDM), the DSI panel rotated to landscape, Firefox, foot
  (ghostty needs OpenGL 3.3; the CM4's V3D only does GL 3.1), crann's
  shells/git/nix-utils/terminal tools and its ai-utils (claude-code +
  claude-obsidian). home-manager comes from crann's input. No VS Code, Obsidian
  app or vault-sync.
- Recovery: the Pi bootloader has no boot menu. If a generation fails to boot,
  take out the SD card and set `os_prefix=nixos/<N>-default/` in `config.txt`
  to a known-good generation. Deploy risky changes with `deploy --boot` and
  reboot: an activation that restarts NetworkManager drops the Wi-Fi SSH
  session and triggers a partial deploy-rs magic rollback.
