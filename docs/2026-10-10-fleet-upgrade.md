# Fleet upgrade — 2026-10-10

Upgrade of the k3s Pi fleet (pi01–pi05, tpi01–tpi04) after a `nix flake update`.
The uConsole is deferred until the k3s hosts are done.

## Summary

| | Before | After |
|---|---|---|
| NixOS | 25.11.20260630.b6018f8 | 26.05.20260724.597283a |
| Kernel | 6.12.47 (booted from an April 2026 generation) | 6.18.34 (`linux_rpi-bcm2711` / `bcm2712`) |
| k3s | v1.35.6+k3s1 | v1.35.8+k3s1 |

This is a **major NixOS release jump** (25.11 → 26.05) and a kernel jump, not a
routine bump. The fleet had last been switched in July 2026 but never rebooted,
so it was still running kernels from April.

## Timeline

Times are local (IST, UTC+1).

| Time | Event |
|---|---|
| 13:47 | `nix flake update` done; all 10 hosts evaluate |
| 13:49 | Full-fleet build started on worf |
| ~13:55 | Worf starts compiling the uConsole kernel (6.12.47) |
| 14:04 | Full-fleet build stopped; k3s-only build started |
| 14:07 | Baseline cluster health recorded |
| ~14:15 | Worf starts compiling `linux_rpi-bcm2711-6.18.34` |
| 14:16 | CNPG switchover: central-4 (picard) promoted |
| 14:48 | bcm2711 kernel still compiling |
| 16:53–17:01 | Worf disk falls 8 GB → 1.2 GB free (99%) during kernel link/install |
| 17:01 | bcm2711 kernel done (~2 h 47 m compile); build tree freed, worf back to 29 GB |
| ~17:03 | Worf starts compiling `linux_rpi-bcm2712-6.18.34` |
| 17:30–17:32 | `nix-store --gc` on worf (approved): 3366 paths, 18.7 GiB freed; 26 GB → 47 GB free. Build unaffected |
| 17:34 | bcm2711 kernel (`out` 42 MiB, `modules` 118 MiB, `dev` 473 MiB) pushed to `jdmacd` cachix; verified (narinfo 200) |
| 19:54 | **bcm2712 kernel build FAILED** in postInstall (~2 h 51 m in): kernel source deleted from worf by the 17:30 GC (see Issues). Build continues (`--keep-going`) for the 7 bcm2711 hosts |
| 19:57 | pi04/pi05 rebuild started; bcm2712 kernel recompiling on worf |
| 20:27 | Pi 4/CM4 build found stalled behind the bcm2712 kernel (262 small drvs + `zfs-kernel` left; picard allows 1 worf job). Restarted with `--builders` override giving worf 2 slots for this build only |

## Flake update

`nix flake update` moved:

| Input | From | To |
|---|---|---|
| nixpkgs | 2026-07-19 (241313f) | 2026-10-08 (e7439b6) |
| nixos-raspberrypi | 2026-07-07 (c845922) | 2026-08-01 (7e39508) |
| nixos-raspberrypi/nixpkgs | 2026-06-30 (b6018f8) | 2026-07-24 (597283a) |
| deploy-rs | 2026-06-16 | 2026-10-07 |
| disko | 2026-06-11 | 2026-09-18 |
| flake-parts | 2026-07-01 | 2026-10-01 |
| sops-nix | 2026-07-04 | 2026-10-09 |

All 10 `nixosConfigurations` evaluated cleanly.

**Note:** the fleet's system version comes from `nixos-raspberrypi`'s own pinned
nixpkgs (597283a), not from our `nixpkgs` input. `nixos-raspberrypi` has no
`inputs.nixpkgs.follows`, and `nixos-raspberrypi.lib.nixosSystem` uses its own
nixpkgs. This is pre-existing behaviour and gives cache hits on the RPi kernels,
so it was left alone.

## Build (remote, on worf)

Built on `worf.jtec.xyz` (aarch64-linux remote builder, `max-jobs = 1`).

- The first attempt built `packages.aarch64-linux.default` (the whole fleet). Worf
  picked up the uConsole kernel (`linux_rpi-bcm2711-6.12.47-stable_20250916`)
  first, and with only one job slot it blocked the rest of the build. That build
  was stopped so the k3s hosts could go first.
- The rebuild covers only the 9 k3s host toplevels. Kernels compiled from source
  (not in any cache): `linux_rpi-bcm2711-6.18.34`, `linux_rpi-bcm2712-6.18.34`,
  plus `zfs-kernel-2.4.3` for each.
- **Why there are no kernel cache hits:** `modules/nixos/rpi-common.nix` adds a
  `kernelPatches` `extraConfig` (`ARM64_VA_BITS_48`, `PGTABLE_LEVELS 4`). That
  changes the kernel's hash, so the stock kernels in `nixos-raspberrypi.cachix.org`
  are never used and every update rebuilds both kernels on worf.
- Worf has 4 cores and 7 GB RAM. One kernel build saturates it (load ~4.4,
  `cores = 0`), so adding a second build slot would not speed things up, and two
  parallel kernel builds would risk running out of memory.
- Worf disk at 15:42: 19 GB free of 75 GB (74% used); inodes 33%. `min-free = 0`,
  so Nix won't garbage-collect automatically, and builds run in `/tmp` on the root
  filesystem. Monitored during the build.
- Status: _in progress_

## Pre-upgrade cluster state

All 10 nodes Ready, all 128 pods Running/Completed, no failed systemd units on
any Pi.

### Ceph (Rook, cluster `turing`)

- 4 OSDs, one per tpi node (osd.2 tpi01, osd.0 tpi02, osd.3 tpi03, osd.1 tpi04).
  4 up and in. 97 PGs active+clean.
- Pools: `.mgr` size 3/min 2; `turing-store-metadata`, `turing-store-data0`,
  `turing-block` size 2/min 1. Losing one node at a time keeps IO running in a
  degraded state.
- **Only 2 mons**: mon-a on tpi04, mon-b on tpi03, each pinned to its node. Quorum
  needs both, so rebooting tpi03 or tpi04 freezes all Ceph IO until the node
  returns. **Decision:** accept the brief IO freeze rather than add a third mon.
- mgr-a runs on tpi01; MDS (active + hot standby) run on picard.
- Health was already `HEALTH_WARN` before the upgrade, with these warnings:
  - `BLUESTORE_SLOW_OP_ALERT`: osd.1 (tpi04), osd.3 (tpi03)
  - `MDS_CLIENT_RECALL`: client picard failing to respond to cache pressure
  - `AUTH_INSECURE_*`: 5 CSI/rbd-mirror client entities using `aes` key type;
    mons allow insecure keys

### CloudNativePG (`cnpg-cluster/central`)

- Before: central-2 primary on pi05, central-3 (pi04) and central-4 (picard)
  standbys. The `central-primary` PDB allows 0 disruptions, so it would have
  blocked draining pi05.
- 14:16 — **switchover: promoted central-4 (picard) to primary.** Picard is not
  part of the Pi fleet, so this one switchover covers the whole upgrade. The
  cluster went healthy straight away with both standbys streaming at zero lag.

## Procedure

Nodes are upgraded one at a time, in this order:

pi01 → pi02 → pi03 → pi04 → pi05 → tpi02 → tpi03 → tpi04 → tpi01

tpi02 is first among the tpi nodes because it has no mon. tpi01 is last because it
is the k3s control plane and runs the Ceph mgr.

For each node:

1. Run the pre-check. Nodes must be Ready and pods healthy. For tpi nodes, Ceph
   must have mon quorum and all PGs active+clean.
2. `kubectl cordon` + `kubectl drain --ignore-daemonsets --delete-emptydir-data`.
3. `deploy --skip-checks .#<node>` (switch; deploy-rs magic rollback stays on).
4. Reboot, then check that the node booted kernel 6.18.34 on NixOS 26.05.
5. Wait for the node to be Ready, then `kubectl uncordon`.
6. Run the post-check (nodes, pods, failed units, Ceph, CNPG).
7. If anything regresses, stop and investigate before the next node.

## Progress log

Times are local. "Down" is the time from reboot until the node is Ready again.

| Node | Start | Drained | Deployed | Rebooted | Ready | Down | Done | Kernel | Notes |
|---|---|---|---|---|---|---|---|---|---|
| pi01 | | | | | | | | | |
| pi02 | | | | | | | | | |
| pi03 | | | | | | | | | |
| pi04 | | | | | | | | | |
| pi05 | | | | | | | | | |
| tpi02 | | | | | | | | | |
| tpi03 | | | | | | | | | mon-b, osd.3 |
| tpi04 | | | | | | | | | mon-a, osd.1 |
| tpi01 | | | | | | | | | control plane, mgr, osd.2 |

## Issues

- **Worf nearly ran out of disk (17:01).** The bcm2711 kernel build tree peaked
  at about 28 GB. Worf went from 29 GB free to 1.2 GB (99%) and recovered only
  because the build finished just in time. `min-free = 0`, so Nix won't GC on its
  own. Each kernel build needs about 30 GB of headroom on worf. Fixes: GC before
  each update, set `min-free`/`max-free` on worf, or give it a larger disk.
- **GC during a remote build broke the bcm2712 kernel (19:54).** The 17:30
  `nix-store --gc` on worf deleted the kernel source
  (`/nix/store/s8ah67…-source`) while the bcm2712 build was running. The
  assumption that Nix protects inputs of in-progress builds does **not** hold for
  remote `ssh-ng` builds: worf's daemon held no root for the source. The compile
  had already unpacked the source, so it ran for ~2 h 50 m and then failed in
  `postInstall` with
  `cp: cannot stat '…-source/arch/arm64/boot/dts/overlays/README'`.
  Lost: one bcm2712 compile (~2 h 50 m). pi04/pi05 are delayed until the rebuild.
  **Lesson: never GC a remote builder while a build is running on it. GC before
  starting the build.**
- Revised order while bcm2712 rebuilds: pi01 → pi02 → pi03 → tpi02 → tpi03 →
  tpi04 → tpi01 → pi04 → pi05 (control plane before two agents is fine for a
  k3s patch bump).

## Deferred

- **The VA_BITS kernel patch is still needed. Keep it.** Background:
  [gist](https://gist.github.com/jDmacD/a1700169e92f1ccd3fa4764443adb969).
  Envoy uses tcmalloc, which on arm64 assumes a 48-bit address space, so Envoy
  fails to start on the RPi kernel's smaller VA size
  ([envoyproxy/envoy#15235](https://github.com/envoyproxy/envoy/issues/15235)).
  - bcm2711 (Pi 4/CM4): defconfig `VA_BITS_39` (3-level) → patched `48`.
  - bcm2712 (Pi 5, 16K pages): defconfig `VA_BITS_47` → patched `48`. 47 bits is
    probably also too small for tcmalloc, so the Pi 5 needs the patch too.
  - Envoy is used heavily: Cilium `enable-l7-proxy`, `loadbalancer-l7: envoy`, the
    Cilium ingress controller, `cilium-envoy` on all 10 nodes, 23
    Ingress/Gateway/HTTPRoute objects, and an Envoy Gateway `GatewayClass`.

  Consequence: the kernels can never come from `nixos-raspberrypi.cachix.org`, so
  every update rebuilds both. Ways to speed that up:
  - An ephemeral, faster aarch64 builder used only during updates (e.g. a Hetzner
    CAX instance added to `/etc/nix/machines`). The gist records a ~20 minute
    kernel build on 8 cores, compared with hours on worf (4 cores).
  - Push the built kernels to `jdmacd` cachix (`build-push`) so SD images and
    rebuilds within the same update cycle don't recompile.

- uConsole: rebuild and deploy after the k3s fleet (its 6.12.47 kernel is not
  cached and needs a long build on worf).
