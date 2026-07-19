# deploy-rs integration.
#
# Turns each host in `flake.nixosConfigurations` into a deploy-rs node so the
# fleet can be pushed with `deploy .#piNN` (or `deploy .` for everything).
# Activation runs as root via passwordless sudo (see modules/nixos/users.nix),
# logging in over SSH as `jmacdonald` (root SSH login is disabled in ssh.nix).
#
# All Pi hosts are aarch64-linux, so their activation packages are built for
# aarch64 — deploy from an aarch64 machine, a remote builder, or with binfmt
# emulation, same as the SD images.
{
  inputs,
  config,
  lib,
  ...
}:
let
  # Every host in the fleet is a Raspberry Pi (aarch64).
  hostSystem = "aarch64-linux";
  deployLib = inputs.deploy-rs.lib.${hostSystem};

  mkNode = name: nixosCfg: {
    # Hosts are reachable on the local .lan domain.
    hostname = "${name}.lan";
    profiles.system.path = deployLib.activate.nixos nixosCfg;
  };
in
{
  flake.deploy = {
    # Log in as the normal user; activation escalates via passwordless sudo.
    sshUser = "jmacdonald";
    user = "root";
    # LAN hosts: push the closure directly instead of via substituters.
    fastConnection = true;
    # magicRollback + autoRollback are on by default; keep them.
    sshOpts = [
      "-o"
      "StrictHostKeyChecking=accept-new"
    ];
    nodes = lib.mapAttrs mkNode config.flake.nixosConfigurations;
  };

  # `nix flake check` validates the deploy schema and that every node's
  # activation package builds. These are aarch64 derivations, so on x86_64
  # they need a remote builder or binfmt emulation.
  perSystem =
    { system, ... }:
    {
      checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
    };
}
