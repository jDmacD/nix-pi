{
  lib,
  pkgs,
  config,
  nixos-raspberrypi,
  ...
}:
{
  # nixos-uconsole's `base`/`kernel`/`configtxt`/`cm` modules (added by
  # mkUConsoleSystem in hosts/default.nix) own the hardware baseline: kernel,
  # config.txt, boot loader, filesystems, console font, NetworkManager and a
  # batteries-included package set. We only layer on the nix-pi bits that don't
  # conflict with that baseline. Notably we do NOT import the whole
  # modules/nixos aggregator (that pulls in k3s + rpi-common, neither of which
  # this handheld wants) — this is why the uConsole skips `mkHost`.
  imports = [
    ../../modules/nixos/users.nix
    ../../modules/nixos/locale.nix
    ../../modules/nixos/sops.nix
    # The SD image module comes from the same nixos-raspberrypi that
    # mkUConsoleSystem builds against (passed in as the `nixos-raspberrypi`
    # arg), so it matches the uConsole kernel/firmware. No USB-gadget
    # networking: the CM4's only USB controller is wired to the internal hub
    # in host mode (no UDC), and the USB-C port is power-only.
    nixos-raspberrypi.nixosModules.sd-image
    ./desktop.nix
  ];

  # Kernel 6.12.87 with its matching firmware bundle, not nixos-raspberrypi's
  # default (6.18.x). All of nixos-uconsole's kernel patches apply cleanly to
  # 6.12.87; on 6.18 `0003-power` (battery reporting) and `0007` need a rebase,
  # and upstream reported a CM4 boot break when it moved nixos-raspberrypi
  # forward. The overlay makes every `pkgs.linuxAndFirmware.default` consumer
  # (raspberrypifw, wireless firmware) agree with the kernel.
  nixpkgs.overlays = [
    (final: prev: {
      linuxAndFirmware = prev.linuxAndFirmware // {
        default = prev.linuxAndFirmware.v6_12_87;
      };
    })
  ];
  boot.kernelPackages = pkgs.linuxAndFirmware.v6_12_87.linuxPackages_rpi4;
  boot.loader.raspberry-pi.firmwarePackage = pkgs.linuxAndFirmware.v6_12_87.raspberrypifw;

  networking.hostName = "uconsole";

  # Cluster admin kubeconfig (the k3s system:admin cert, as on picard) for
  # jmacdonald's crann kubernetes tools (home.nix). Its own sops file, encrypted
  # to the uConsole and jmacdonald only, not to the Pis (see .sops.yaml).
  # ~/.kube is created first so kubectl/k9s can write their cache beside it.
  systemd.tmpfiles.rules = [ "d /home/jmacdonald/.kube 0750 jmacdonald users -" ];
  sops.secrets.kubeconfig = {
    sopsFile = ./secrets.yaml;
    owner = "jmacdonald";
    mode = "0400";
    path = "/home/jmacdonald/.kube/config";
  };
  networking.networkmanager.enable = true;
  # brcmfmac power save adds latency and jitter (laggy SSH, missed probes).
  networking.networkmanager.wifi.powersave = false;

  # The factory 4G card: a SIMCom SIM7600G-H (USB 1e0e:9001, option + qmi_wwan,
  # GNSS built in). It stays unpowered until `uconsole-4g enable` (GPIO 24 high
  # plus a GPIO 15 pulse, which borrows UART1's RX pin). This adds that script;
  # ModemManager already comes with NetworkManager, so mobile data works once a
  # SIM is in. `uconsole-4g disable` didn't power it off when tested 2026-11-13;
  # use `mmcli -m 0 --set-power-state-off` or AT+CPOF on /dev/ttyUSB2 instead.
  hardware.uc-4g.enable = true;

  # Keep tty1 readable. nixos-raspberrypi sets loglevel 7, and the firewall
  # logs every refused packet, so both end up on the uConsole's screen.
  boot.consoleLogLevel = lib.mkForce 3;
  networking.firewall.logRefusedConnections = false;

  # nix-pi's ssh policy: key-only, no root login. Upstream's `base` enables
  # openssh with password + root login, so force ours over it.
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    PermitRootLogin = lib.mkForce "no";
  };

  # No out-of-tree rtl8812au for the external USB Wi-Fi dongle: it needs the
  # kernel's `dev` output, which the uConsole Cachix doesn't carry, so it forces
  # a full kernel rebuild. On 26.05 (kernel 6.14+) the in-tree rtw88_8812au
  # driver covers the dongle instead.
  #
  # ZFS is off for the same reason: nixpkgs' profiles/base.nix (via the SD-image
  # profile) defaults it on, and zfs-kernel also needs the kernel's `dev` output.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    wirelesstools
    iw
    git
    # Manual keyboard firmware tool (QMK: Start = Super for niri). Never runs
    # on its own; see keyboard-flash.nix.
    (callPackage ./keyboard-flash.nix { })
  ];

  # No serial console on this board.
  systemd.services."serial-getty@ttyS0".enable = false;

  # nixos-uconsole's base does not set a stateVersion; match the fleet default.
  system.stateVersion = "25.05";
}
