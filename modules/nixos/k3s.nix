{
  config,
  pkgs,
  lib,
  ...
}:
# Single k3s module for the whole fleet. `tpi01` is the control-plane server;
# every other host joins it as an agent. The role — and the server-only flags —
# are selected from the hostname, so this module can be imported unconditionally
# for all hosts (see ../nixos/default.nix).
let
  serverHost = "tpi01";
  isServer = config.networking.hostName == serverHost;
in
{
  networking.firewall.enable = false;
  networking.firewall.checkReversePath = false;
  networking.firewall.allowedTCPPorts = [
    6443 # k3s API server
    10250 # metrics port
    4240 # cilium health
    443
    80
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel/cilium vxlan (inter-node networking)
  ];

  # Cluster join token, shared by the server (as its bootstrap token) and every
  # agent. Managed with sops so the value is identical across the fleet — a bare
  # server would otherwise generate a random token the agents can't match.
  sops.secrets."k3s/token".owner = "root";

  # https://search.nixos.org/options?channel=25.05&query=services.k3s
  services.k3s = {
    enable = true;
    package = pkgs.k3s_1_35;
    role = if isServer then "server" else "agent";
    tokenFile = config.sops.secrets."k3s/token".path;
    serverAddr = lib.mkIf (!isServer) "https://${serverHost}.lan:6443";
    extraFlags = toString (
      # --node-name on all roles: otherwise the node registers under the
      # nixos-rpi bootstrapper hostname instead of its own.
      [ "--node-name ${config.networking.hostName}" ]
      ++ lib.optionals isServer [
        "--disable=traefik"
        "--write-kubeconfig-mode=644"
        "--flannel-backend=none"
        "--disable-network-policy"
        "--disable-kube-proxy"
        "--disable=servicelb"
        "--tls-san ${serverHost}.lan"
      ]
    );
  };

  # needed for ceph
  fileSystems."/lib/modules" = {
    device = "/run/booted-system/kernel-modules/lib/modules";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/run/booted-system/kernel-modules/lib/modules" ];
  };

  programs.nbd.enable = true; # required for ceph

  environment.systemPackages = with pkgs; [
    lvm2
  ];
}
