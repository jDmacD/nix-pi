{
  config,
  inputs,
  ...
}:
# Fleet wiring for crann's k3s module (inputs.crann.modules.nixos.k3s), which
# owns the firewall holes, Ceph prerequisites, kubelet eviction thresholds and
# the k3s package (pinned through nixpkgs-multiverse by crann.k3s.version).
# `tpi01` is the control-plane server; every other host joins it as an agent.
# The role — and the server-only flags — are selected from the hostname, so
# this module can be imported unconditionally for all hosts (see
# ../nixos/default.nix).
let
  serverHost = "tpi01";
  isServer = config.networking.hostName == serverHost;
in
{
  imports = [ inputs.crann.modules.nixos.k3s ];

  # Cluster join token, shared by the server (as its bootstrap token) and every
  # agent. Managed with sops so the value is identical across the fleet — a bare
  # server would otherwise generate a random token the agents can't match.
  sops.secrets."k3s/token".owner = "root";

  crann.k3s = {
    enable = true;
    role = if isServer then "server" else "agent";
    serverAddr = "https://${serverHost}.lan:6443";
    tokenFile = config.sops.secrets."k3s/token".path;
    extraFlags =
      if isServer then
        [
          "--disable=traefik"
          "--write-kubeconfig-mode=644"
          "--flannel-backend=none"
          "--disable-network-policy"
          "--disable-kube-proxy"
          "--disable=servicelb"
          "--tls-san ${serverHost}.lan"
          # The control plane runs inside the k3s process, outside any pod, so
          # the scheduler can't see it. Measured 2026-10-26: k3s-server ~2.4Gi
          # anon memory and ~560m CPU on tpi01 (node used 68% of memory while
          # pod requests were 41%). Reserve it so allocatable reflects what's
          # left. Pods' cgroup is capped at allocatable (enforce: pods).
          "--kubelet-arg=kube-reserved=cpu=600m,memory=2816Mi"
          "--kubelet-arg=system-reserved=cpu=100m,memory=256Mi"
        ]
      else
        [ ];
  };
}
