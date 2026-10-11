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

**Outcome: complete.** All 9 k3s Pi hosts were upgraded and rebooted one at a
time (13:47 → 01:54, mostly spent building kernels on worf). Per-node reboot
downtime was 57 s–2 m 29 s. One unplanned **~7 min cluster-wide Ceph IO outage
(23:47–23:54)** happened when mon-a's store on tpi04 corrupted while tpi04 was
untouched. It was recovered by restoring quorum to mon-b, and the mons are now
b (tpi03) + c (picard). Weekly Nix GC was added to the fleet along the way. See
**Issues** for everything that went wrong and **Follow-ups** for what's left.

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
| 21:03 | Pi 4/CM4 closures built (7 hosts) |
| 21:03–21:36 | pi01 upgraded (see progress log) |
| ~21:36 | **picard hard crash** during pi02 deploy; back up 21:37:35 |
| 22:17 | Session resumed; cluster checked, healthy |
| 22:19 | bcm2712 rebuild restarted (killed by the crash) |
| 22:19–00:32 | pi02, pi03, tpi02, tpi03, tpi04, tpi01 upgraded (see progress log) |
| 23:47–23:54 | **Ceph quorum lost** (mon-a store corruption on tpi04); restored to mon-b, then mon-c on picard |
| 00:37–00:42 | Weekly GC config (2a6f52b) rolled out by live switch to the 7 upgraded hosts |
| ~01:31 | bcm2712 kernel done (third attempt; ~3 h 10 m compile) |
| 01:33 | bcm2712 kernel (`out` 42 MiB, `modules` 117 MiB, `dev` 473 MiB) pushed to `jdmacd` cachix; verified |
| 01:45 | pi04/pi05 profiles (with GC config) built |
| 01:46–01:54 | pi04, pi05 upgraded. **Fleet complete** |

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
- Status: done. bcm2711 built once (~2 h 47 m). bcm2712 needed three
  attempts: GC-deleted source, then the picard crash, then success at ~01:31
  (~3 h 10 m). Both kernels are in `jdmacd` cachix.

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
3. `deploy --skip-checks --boot .#<node>`. This is **not** a live switch: the
   dbus-broker change can't be switched live (see Issues).
4. Reboot, then check that the node booted kernel 6.18.34 on NixOS 26.05.
5. Wait for the node to be Ready, then `kubectl uncordon`.
6. Run the post-check (nodes, pods, failed units, Ceph, CNPG).
7. If anything regresses, stop and investigate before the next node.

## Progress log

Times are local. "Down" is the time from reboot until the node is Ready again.

| Node | Start | Drained | Deployed | Rebooted | Ready | Down | Done | Kernel | Notes |
|---|---|---|---|---|---|---|---|---|---|
| pi01 | 21:03:44 | 21:04:17 | 21:31:54 | 21:32:00 | 21:34:03 | 2m03s | 21:35:54 | 6.18.34 ✅ | Deploy delayed ~27 min (see Issues: activatable build stall, dbus-broker). Envoy OK on VA_BITS=48 |
| pi02 | 21:36 / 22:19:14 | 21:36 | 22:22:33 | 22:22:34 | 22:25:03 | 2m29s | 22:25:55 | 6.18.34 ✅ | Drained just before the picard crash; resumed 22:19 |
| pi03 | 22:26:26 | 22:27:22 | 22:31:02 | 22:31:02 | 22:32:41 | 1m39s | 22:33:38 | 6.18.34 ✅ | Uncordoned ~1 min early on stale status (see Issues); pods healthy 22:33:38 |
| pi04 | 01:46:08 | 01:46:11 | 01:47:46 | 01:47:46 | 01:48:43 | 57s | 01:49:34 | 6.18.34 ✅ | Pi 5 (16K pages). Hosts one replica of each Envoy Gateway DaemonSet (external .249, internal .251, tls-passthrough .250:5432); all reachable after. CNPG standby central-3 (local-path) Pending until uncordon, then 3/3 healthy |
| pi05 | 01:50:22 | 01:50:26 | 01:52:16 | 01:52:16 | 01:53:13 | 57s | 01:53:59 | 6.18.34 ✅ | Pi 5. Other Envoy Gateway replicas; CNPG standby central-2. After: CNPG 3/3 healthy, gateways .249/.251:443 and .250:5432 open, Jellyfin 200 via gateway |
| tpi02 | 22:34:25 / 22:40:46 | 22:48:55 | 22:51:19 | 22:51:19 | 22:52:54 | 1m35s | 22:55:46 | 6.18.34 ✅ | 1st try failed: /nix full (see Issues). GC freed 19.2 GiB (100% → 31%). Ceph 97 active+clean 22:55:46 |
| tpi03 | 22:56:14 | 23:13:02 | 23:15:34 | 23:15:35 | 23:17:07 | 1m32s | 23:18:48 | 6.18.34 ✅ | mon-b, osd.3. GC freed 16.9 GiB (97% → 31%), took 16 min. mon-b kept running through drain/deploy (`--pod-selector app!=rook-ceph-mon`): **Ceph IO freeze ~2 min** (quorum lost 23:15:35, re-formed ~23:17:35). Ceph 97 active+clean (1 deep-scrubbing) by ~23:36 |
| tpi04 | 00:13:24 | 00:21:47 | 00:25:11 | 00:25:11 | 00:27:00 | 1m49s | 00:32:01 | 6.18.34 ✅ | Paused 23:18–00:12 by user (mon-a corruption incident, see Issues). No mon on tpi04 by then. GC freed 16.1 GiB (96% → 31%). 0 storage errors in dmesg before, during and after. osd.1 BlueStore warnings (slow ops, spurious reads) cleared after restart |
| tpi01 | 23:55:59 | 00:03:46 | 00:06:30 | 00:06:30 | 00:08:26 | 1m56s | 00:11:42 | 6.18.34 ✅ | Control plane, mgr, active MDS, osd.2. GC freed 17.1 GiB (97% → 31%). **k8s API down ~2 min** during reboot. No mon on tpi01 by then (mons b/tpi03, c/picard): no Ceph IO freeze |

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
- **deploy-rs stalled on worf's single slot (21:04–21:14).** deploy-rs builds a
  small aarch64 `activatable-nixos-system-*` wrapper, which queued behind the
  bcm2712 kernel. Fixed by pre-building all 7 wrappers
  (`.#deploy.nodes.<h>.profiles.system.path`) with the 2-slot `--builders`
  override (21:14–21:23).
- **Live switch fails: D-Bus implementation change (pi01, 21:30).** NixOS 26.05
  moves the default from `dbus-daemon` to **`dbus-broker`**, which can't be
  hot-swapped (`Failed to reload dbus-broker.service`). `switch-to-configuration`
  errored, so deploy-rs auto-rolled back. The rollback was only partial:
  `/run/current-system` and the boot default were left on the new system while
  the profile link went back to generation 36. **Fix: `deploy --boot` + reboot**,
  which is needed for the kernel anyway. pi01 recovered cleanly this way, and all
  remaining hosts use `--boot`.
- **picard crashed (~21:36).** The journal for the previous boot stops abruptly at
  21:31:44 with no shutdown sequence, so this was a hard crash or power loss, not
  a clean or automatic reboot. The cause is unknown: pstore is unreadable without
  root and no MCE/thermal errors were logged. picard came back at 21:37:35,
  booting its newest installed generation (kernel 6.18.38 → 6.18.55). Effects:
  - The Claude session driving the upgrade died. pi02 was left cordoned and
    drained but **not** deployed. Its deploy had just started, and pi02 is still
    on 25.11.
  - The bcm2712 rebuild (client on picard) was killed after ~1 h 40 m; restarted
    at 22:19.
  - CNPG `central` recovered by itself; central-4 on picard is still primary
    with zero lag. Ceph: 97 PGs active+clean, MDS + hot standby up, mon quorum
    re-formed.
  - Two GPU pods on picard (`open-webui/kokoro`, `open-webui/ollama`) were
    rejected with `UnexpectedAdmissionError` (kubelet started before the NVIDIA
    device plugin). Their replacements are Running; the rejected pods are stale
    leftovers.
- **Stale Ready status after a fast reboot (pi03, 22:32).** pi03 was back on SSH
  in 74 s, before the control plane had marked it NotReady, so the script read
  the pre-reboot `Ready`/`Running` status and uncordoned about 1 min before its
  DaemonSet pods had actually restarted. Impact was negligible. The script now
  waits for the node's `bootID` to change and for every pod container on it to
  have started after the reboot time.
- **tpi `/nix` partitions full (tpi02, 22:35).** The tpi nodes mount `/nix` on a
  separate **32 GB** partition (`sda1`). With 26–30 system generations kept
  since Dec 2025 and no automatic GC, they were at 95–100% (tpi02: 0 bytes free).
  tpi02's deploy failed copying the closure (`No space left on device`), after
  the drain had already taken osd.0 down (32 PGs degraded). Recovery: uncordoned
  tpi02 on its old system; osd.0 back and 97 PGs active+clean within ~2 min.
  Fix (approved): before each tpi upgrade,
  `nix-env -p /nix/var/nix/profiles/system --delete-generations +3` +
  `nix-store --gc`. Only 2 generations are bootable anyway
  (`configurationLimit = 2`).
  **Done (2a6f52b, rolled out 00:37–00:42):** `host-shared.nix` now has a weekly
  `nix.gc` (6 h randomised delay) that first prunes the system profile to the
  last 3 generations, so not by age (`--delete-older-than` would remove the
  only rollback on infrequent updates), then collects unreferenced paths.
  Plus `min-free = 2 GiB` / `max-free = 8 GiB` as a copy-time safety net.
  Deployed by live switch to the 7 upgraded hosts; only `nix-daemon` restarted,
  no failed units, Ceph untouched. pi04/pi05 get it with their upgrade.
  Enlarging `/nix` on the CM4 hosts is still an option.
- **New Ceph warning on osd.1 (tpi04), seen 23:36:**
  `BLUESTORE_SPURIOUS_READ_ERRORS` (osd.1: 2 reads needed retries), on top of the
  pre-existing `BLUESTORE_SLOW_OP_ALERT` for osd.1. This appeared during
  recovery/scrub IO after tpi03. All PGs are clean, but it is a possible early
  sign of a flaky SSD/cable/controller on tpi04. Recommend checking SMART and
  `dmesg` on tpi04 before rebooting it. (osd.3's slow-op warning cleared after
  its restart.)
  **Checked 23:4x (read-only):** Samsung 870 QVO 4 TB over USB/UAS. SMART
  PASSED; 0 reallocated sectors, 0 uncorrectable, 0 CRC, 0 bad blocks; 79% wear
  left at 26,404 h; 27 °C. No I/O, USB reset or UAS errors in `dmesg`. This
  points to QLC (QVO) + USB latency under sustained recovery/scrub IO rather
  than media failure. Keep monitoring; it does not block a reboot.
- **🚨 Ceph quorum lost: mon-a store corrupt (23:47–23:54).** tpi04 had not
  been touched (paused; not drained, rebooted or redeployed). At **23:47:24**
  `rook-ceph-mon-a` crashed with
  `rocksdb … Corruption: block checksum mismatch … store.db/1320763.sst` →
  `ceph_abort_msg("failed to write to db")`, and crashlooped (6 restarts). With
  only 2 mons, that meant **no quorum: all CephFS/RBD IO frozen cluster-wide**
  (Jellyfin `/config` hung; picard's kernel client got `EHOSTUNREACH` to mon-a).
  - The mon store is on tpi04's `/var` (`sda2`), the **same USB-attached 870 QVO**
    that reported `BLUESTORE_SPURIOUS_READ_ERRORS` for osd.1 shortly before. The
    earlier "SMART clean, probably fine" read on that disk was **wrong**: the
    storage path (disk, USB bridge or cable) is corrupting or misreading data.
    Treat tpi04's storage as suspect. osd.1 on the same disk is still up.
  - Note: a read-only `smartctl` query over the USB bridge ran a few minutes
    before the crash. Some USB-SATA bridges misbehave under SMART passthrough.
    Not proven to be related (the read retries came first), but recorded.
  - **Recovery (approved):** `kubectl rook-ceph mons restore-quorum b` (plugin
    via `nix-shell -p kubectl-rook-ceph`). mon-b (tpi03, intact, `probing`)
    formed quorum alone at **~23:54**; IO resumed immediately; mon-a was purged
    from the monmap (its corrupt store is left on disk on tpi04 for analysis). The
    operator then created **mon-c on picard**; quorum b,c by ~23:55.
    **Ceph IO outage: ~7 min (23:47 → 23:54).**
  - Jellyfin recovered on its own (`/health` 200; error burst at 23:54:27 when
    IO resumed). `reactive-resume` (picard) failed probes during the freezes and
    restarted.
- **Health gate too strict (tpi03).** The post-upgrade Ceph gate required exactly
  `active+clean`, so a routine deep scrub (`active+clean+scrubbing+deep`) kept it
  waiting. It now accepts any `active+clean*` state.
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

## Follow-ups

- **Ceph: go to 3 mons.** With 2, either mon failing stops all IO; that
  happened tonight (mon-a corruption). Patch CephCluster `turing`
  `spec.mon.count: 3`.
- **tpi04 storage.** mon-a's RocksDB corrupted on tpi04's USB-attached 870 QVO
  (`/var` = `sda2`; osd.1 is on `sda3`). SMART is clean and there are no kernel
  errors, so suspect the USB bridge/cable or QLC behaviour under load. Inspect
  or replace before trusting it; the corrupt store is still on disk at
  `/var/lib/rook/mon-a`.
- **worf disk headroom.** Set `min-free`/`max-free` on worf (a kernel build
  tree peaks at ~28 GB on a 75 GB disk). Never GC worf while it is building:
  remote builds hold no GC roots for their inputs.
- **picard's crash (~21:36) is unexplained.** Check `pstore`/BMC/power as root.
  picard now runs mon-c, the active MDS and the CNPG primary.
- Delete the two stale `UnexpectedAdmissionError` GPU pods in `open-webui`.
- Optionally give worf more build slots for small derivations, so they don't
  queue behind a kernel (tonight's 2-slot `--builders` override worked well).
- uConsole: rebuild and deploy (its 6.12.47 kernel is not cached and needs a
  long build on worf).

## Procedure that worked (for next time)

1. GC worf **before** starting the build; push kernels to cachix after.
2. Pre-build `.#deploy.nodes.<h>.profiles.system.path` for all hosts so
   deploy-rs never waits on the builder.
3. Per node: (tpi: Ceph healthy gate, then prune generations + GC) → cordon/drain
   (on mon nodes `--pod-selector app!=rook-ceph-mon`) → `deploy --boot` →
   reboot → wait for a **new `bootID`** + Ready + pods started after the reboot →
   uncordon → (tpi: wait for all PGs `active+clean*`).
4. Order: agents, then the tpi nodes without a mon, then mon nodes, then the
   control plane.
