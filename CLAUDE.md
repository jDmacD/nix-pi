# nix-pi

NixOS flake for a fleet of Raspberry Pi hosts (a homelab / k3s cluster), built
with [flake-parts](https://flake.parts) and
[nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

## Layout

```
flake.nix                     # inputs + flake-parts mkFlake entrypoint
deploy.nix                    # deploy-rs nodes + flake checks
hosts/
  default.nix                 # mkHost helper, host list, sdImage packages
  piNN/configuration.nix      # per-host module (imports a profile)
  piNN/disk-configuration.nix # disko layout (Pi 5 / NVMe hosts only)
  uconsole/configuration.nix  # ClockworkPi uConsole (non-cluster; nixos-uconsole)
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
`k3s`, so every cluster host picks them up automatically. Non-cluster hosts
(the uConsole) don't import this aggregator at all — that's how they skip k3s.

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

## Non-cluster hosts (uConsole)

Not every host is a k3s Pi. The **uConsole** (ClockworkPi handheld, CM4) is the
worked example — see `hosts/uconsole/README.md`. Key differences from a fleet
Pi:

- Its hardware support comes from the `nixos-uconsole` input (uConsole kernel,
  `config.txt`, CM module), which layers on the **stock** `nixos-raspberrypi` —
  no fork, no input conflict. It is left on its own pinned nixpkgs (25.11) +
  `nixos-raspberrypi` tag rather than following our unstable: that pin is a
  matched pair, and feeding the tag unstable breaks the RPi platform
  (`stdenv.hostPlatform.linux-kernel` missing). So the uConsole runs 25.11 while
  the fleet runs unstable.
- It **does not** use `mkHost`. It is built in `hosts/default.nix` with
  `nixos-uconsole.lib.mkUConsoleSystem { variant = "cm4"; ... }`, which pulls in
  the uConsole hardware modules and wraps `nixos-raspberrypi.lib.nixosSystem`.
  nix-pi's `inputs` are threaded through `specialArgs` so the shared modules the
  host imports still resolve (e.g. `inputs.sops-nix`).
- It is **not** a cluster node, so it never imports `modules/nixos` (the
  k3s/rpi-common aggregator). Instead its `configuration.nix` cherry-picks just
  the shared modules it wants (`users`, `locale`, `sops`) and takes the rest of
  the system baseline from `mkUConsoleSystem`'s own `base` module. That upstream
  `base` enables password/root SSH, so the host re-asserts nix-pi's key-only,
  no-root SSH policy with `lib.mkForce`.
- It is a normal deploy-rs node (`uconsole.lan`, reachable over its USB-gadget /
  LAN port) and gets a `.#uconsole-sdImage` package for initial provisioning.

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

## Deploying (deploy-rs)

`deploy.nix` is a flake-parts module that maps every `flake.nixosConfigurations`
host into a `flake.deploy.nodes.<host>` entry, so the whole fleet is deployable
with [deploy-rs](https://github.com/serokell/deploy-rs). It also exposes
`flake.checks.<system>` (the schema/activation checks from
`deploy-rs.lib.<system>.deployChecks`), so `nix flake check` validates the deploy
config.

Node conventions (set once at the top of `deploy.nix`, inherited by all nodes):

- `hostname` is `<host>.lan` (the local domain).
- `sshUser = "jmacdonald"` — root SSH login is disabled (`ssh.nix`), so deploy
  logs in as the normal user and escalates via passwordless sudo
  (`security.sudo.wheelNeedsPassword = false` in `users.nix`); `user = "root"`
  runs the activation.
- `fastConnection = true` — LAN hosts, so the closure is copied directly.
- Activation packages are `aarch64-linux`, so deploying (and the checks) needs
  an aarch64 machine, a remote builder, or binfmt emulation — same as the SD
  images.

```
deploy .#pi04          # deploy one host
deploy .               # deploy the whole fleet
deploy .#pi04 --dry-activate
```

The `deploy-rs` CLI is in the devShell (`shell.nix`).

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
nix build                # build every host's system closure (packages.default)
nix build .#piNN-sdImage # build a host's SD image
nix fmt                  # format (nixfmt-tree)
```

`packages.default` (aarch64 only) is a `linkFarm` of every host's
`system.build.toplevel`, so a bare `nix build` confirms the whole fleet builds
without producing full SD images.

## Conventions

- `system.stateVersion` is a `mkDefault "25.05"` in `modules/nixos/default.nix`;
  override per host only when a machine genuinely differs.
- Keep board/module-set differences in `modules/nixos/profiles/`, machine-unique
  settings in `hosts/piNN/configuration.nix`, and truly shared config in
  `modules/nixos/rpi-common.nix`.
- Inputs: `nixpkgs` (unstable), `flake-parts`, `nixos-raspberrypi`, `disko`,
  `sops-nix`, `deploy-rs`, and the uConsole-only `nixos-uconsole`.
