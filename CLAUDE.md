# nix-pi

NixOS flake for a fleet of Raspberry Pi hosts (a homelab / k3s cluster), built
with [flake-parts](https://flake.parts) and
[nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

## Layout

```
flake.nix                     # inputs + flake-parts mkFlake entrypoint
hosts/
  default.nix                 # mkHost helper, host list, sdImage packages
  piNN/configuration.nix      # per-host module (imports a profile)
  piNN/disk-configuration.nix # disko layout (Pi 5 / NVMe hosts only)
modules/nixos/
  default.nix                 # shared module aggregator; stateVersion default
  rpi-common.nix              # boot/kernel/packages common to all Pis
  host-shared.nix             # nix settings, timezone, fwupd, zram
  locale.nix                  # locale / keymap
  ssh.nix                     # openssh
  users.nix                   # user accounts + authorized keys
  sops.nix                    # sops-nix module + default secrets file
  k3s.nix                     # whole-fleet k3s (role selected by hostname)
  profiles/pi4.nix            # module set for Raspberry Pi 4 hosts
  profiles/pi5.nix            # module set for Raspberry Pi 5 hosts (+ disko)
  profiles/cm4.nix            # module set for CM4 hosts (tpiNN) (+ disko)
hosts/
  secrets.yaml                # sops-encrypted fleet secrets (k3s token, ...)
.sops.yaml                    # sops recipient keys + creation rules
```

`default.nix` imports `rpi-common`, `host-shared`, `locale`, `ssh`, `sops`, and
`k3s`, so every host picks them up automatically.

## How hosts are declared

flake-parts has **no built-in NixOS host abstraction**, so `hosts/default.nix`
populates the standard `flake.nixosConfigurations` output directly. Each host is
built with `inputs.nixos-raspberrypi.lib.nixosSystem` (not `nixpkgs.lib.nixosSystem`)
— that wrapper injects the `nixos-raspberrypi` module argument and the required
RPi overlays. Building a Pi host with plain `nixpkgs.lib.nixosSystem` fails with
`error: attribute 'nixos-raspberrypi' missing`.

A `mkHost` helper removes the per-host boilerplate: it threads `inputs` through
`specialArgs`, imports `../modules/nixos`, and derives `networking.hostName` from
the attribute name. The host list is **explicit** (no `readDir` auto-discovery,
by preference).

### Adding a host

1. Create `hosts/piNN/configuration.nix` importing the right profile
   (`profiles/pi4.nix` or `profiles/pi5.nix`), plus `./disk-configuration.nix`
   for NVMe/Pi 5 hosts.
2. Add one line to `hosts/default.nix`: `piNN = mkHost "piNN";`.
3. The host automatically gets a `.#piNN-sdImage` package.

## Profiles

- **pi4** — `raspberry-pi-4.base`, `sd-image`, `usb-gadget-ethernet`.
- **pi5** — `raspberry-pi-5.base`, `raspberry-pi-5.page-size-16k`, `sd-image`,
  `usb-gadget-ethernet`, plus `disko`. Pi 5 hosts declare an NVMe layout in
  their own `disk-configuration.nix`.
- **cm4** — `raspberry-pi-4.base`, `sd-image`, `usb-gadget-ethernet`, plus
  `disko`. Used by the `tpiNN` (Turing Pi CM4) hosts, which declare their own
  `disk-configuration.nix`.

`sd-image` owns the SD-card filesystem layout — do **not** also declare
`fileSystems` for `/` and `/boot/firmware`, they conflict.

## k3s cluster

`modules/nixos/k3s.nix` is imported by **every** host (via `default.nix`). It is
a single module that picks the k3s role from the hostname:

- `tpi01` → `server` (control plane). Gets the server-only flags: no traefik,
  no servicelb, `--flannel-backend=none`, `--disable-network-policy`,
  `--disable-kube-proxy` (networking is handed to Cilium), and a `--tls-san` for
  `tpi01.lan`.
- **every other host** → `agent`, joining `https://tpi01.lan:6443`.

To move/duplicate the control plane, change the `serverHost` binding (or make
`isServer` a list membership test) — that is the single source of truth. A
second server also needs the etcd ports (2379/2380) opened and `--cluster-init`
on the first node.

Both roles read the **same** join token from sops (`k3s/token`), so the cluster
token is deterministic across the fleet — a bare server would otherwise generate
a random token the agents can't match. All roles also set `--node-name` so nodes
register under their real hostname, not the nixos-rpi bootstrapper's.

Ceph support (bind-mount of `/lib/modules`, `programs.nbd`, `lvm2`) lives in the
same module since it is needed cluster-wide.

## Secrets (sops-nix)

Fleet secrets live in `hosts/secrets.yaml`, encrypted with `sops` to the age
keys declared in `.sops.yaml`. `modules/nixos/sops.nix` wires in `sops-nix` and
sets that file as the default. Secrets are consumed via
`config.sops.secrets."<name>".path` (e.g. the k3s token).

After adding/removing a host key in `.sops.yaml`, re-key the file so its
recipients match:

```
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
nix-shell -p sops --run "sops updatekeys hosts/secrets.yaml"
```

## Building images

Each host's SD image is exposed as a package:

```
nix build .#piNN-sdImage
```

Images are **aarch64** builds and only appear under the `aarch64-linux` package
set. On an x86_64 machine build them via a remote aarch64 builder or with
`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` enabled.

## Common commands

```
nix flake check          # evaluate all configs (add --all-systems for aarch64)
nix build .#piNN-sdImage # build a host's SD image
nix fmt                  # format (nixfmt-tree)
```

## Conventions

- `system.stateVersion` is a `mkDefault "25.05"` in `modules/nixos/default.nix`;
  override per host only when a machine genuinely differs.
- Keep board/module-set differences in `modules/nixos/profiles/`, machine-unique
  settings in `hosts/piNN/configuration.nix`, and truly shared config in
  `modules/nixos/rpi-common.nix`.
- Inputs: `nixpkgs` (unstable), `flake-parts`, `nixos-raspberrypi`, `disko`.
