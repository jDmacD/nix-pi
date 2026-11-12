# uConsole desktop: niri + noctalia from crann, home-manager for jmacdonald.
#
# Mirrors blueprint's desktop module (used by lwh-hotapril), trimmed for a
# 5" 720x1280 portrait panel on a CM4 (4 GB, VideoCore VI / GLES 3.1):
# - no GDM (pulls in much of GNOME); greetd + tuigreet starts niri instead;
# - no stylix, thunar or VS Code;
# - 32-bit ALSA off (aarch64 has no 32-bit userland here).
{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    inputs.crann.modules.nixos.niri
    inputs.crann.modules.nixos.noctalia
    inputs.crann.modules.nixos.desktop
    # crann's home-manager input follows crann's nixpkgs, which follows ours.
    inputs.crann.inputs.home-manager.nixosModules.home-manager
  ];

  crann.niri = {
    enable = true;
    extraSettings = {
      spawn-at-startup = [
        { command = [ "noctalia" ]; }
      ];
      # The CWU50 panel is natively portrait (720x1280); rotate it to landscape.
      outputs."DSI-1" = {
        transform.rotation = 90;
        scale = 1.0;
      };
    };
  };

  crann.noctalia.cache.enable = true;

  # claude-code and bws (crann ai-utils/terminal) are unfree, as on blueprint.
  nixpkgs.config.allowUnfree = true;

  crann.desktop = {
    enable = true;
    audio.support32Bit = false;
  };

  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
  };

  # Browser: Firefox from cache.nixos.org. Chromium is heavier on 4 GB.
  programs.firefox.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = { inherit inputs; };
    users.jmacdonald = import ./home.nix;
  };
}
