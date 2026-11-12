# home-manager for jmacdonald on the uConsole: noctalia, CLI tools and the
# Claude stack from crann. Kept small for the handheld: no VS Code, Obsidian
# app or vault-sync (no Codeberg key on this device).
{
  inputs,
  ...
}:
{
  imports = with inputs.crann.modules.homeManager; [
    noctalia
    desktop
    terminal
    shells
    git
    nix-utils
    ai-utils
    kubernetes
    helix
  ];

  crann = {
    noctalia.enable = true;
    desktop.enable = true;
    terminal = {
      enable = true;
      # ghostty needs OpenGL 3.3; the CM4's V3D only does GL 3.1 / GLES 3.1.
      # foot is what crann's niri binds launch anyway.
      ghostty.enable = false;
      foot.enable = true;
    };
    shells.enable = true;
    git.enable = true;
    nix-utils.enable = true;
    # kubectl, helm, k9s etc.; kubeconfig from sops (configuration.nix).
    kubernetes.enable = true;
    # Helix as $EDITOR, with language servers.
    helix.enable = true;
    ai-utils = {
      enable = true;
      claude-code = {
        enable = true;
        context = ''
          - This is a NixOS machine: a ClockworkPi uConsole handheld (Raspberry Pi CM4, 4 GB, 5" 1280x720 screen)
          - Its hostname is uconsole; its config lives in the nix-pi repo (hosts/uconsole)
          - The local network domain name is .lan
          - The local subnet is 192.168.178.0/24
          - The user's timezone is Europe/Dublin (IST, UTC+1, in summer; GMT, UTC+0, in winter). Clusters, logs and alerts use UTC, so give the user times in local time too
          - The nix-shell can be used to access tools, for instance `nix-shell --packages dnsutils --quiet --run "dig +short picard.lan"`
        '';
      };
      claude-obsidian.enable = true;
    };
  };

  home.stateVersion = "26.05";
}
