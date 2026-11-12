# uConsole desktop: niri + noctalia from crann, home-manager for jmacdonald.
#
# Mirrors blueprint's desktop module (used by lwh-hotapril), trimmed for a
# 5" 720x1280 portrait panel on a CM4 (4 GB, VideoCore VI / GLES 3.1):
# - GDM login screen (gnome-shell greeter) starting niri;
# - no stylix, thunar or VS Code;
# - 32-bit ALSA off (aarch64 has no 32-bit userland here).
{
  inputs,
  lib,
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
      # The QMK keyboard firmware (j1n6/qmk-uconsole, see keyboard-flash.nix)
      # sends keycodes for a US ANSI layout; under crann's `ie` layout @/",
      # #/£ etc. come out swapped. Forced because crann sets it as a plain value.
      input.keyboard.xkb.layout = lib.mkForce "us";
      spawn-at-startup = [
        { command = [ "noctalia" ]; }
      ];
      # The CWU50 panel is natively portrait (720x1280), but its kernel
      # driver sets the DRM "panel orientation" property, which niri already
      # applies (effective 270°, 1280x720 landscape). A transform here is
      # added on top of it: `90` cancelled it out and left the desktop
      # sideways. So no transform.
      outputs."DSI-1".scale = 1.0;
    };
  };

  crann.noctalia.cache.enable = true;

  # Same US layout for GDM (xkb) and the text console; modules/nixos/locale.nix
  # sets gb/uk for the other hosts.
  services.xserver.xkb.layout = lib.mkForce "us";
  console.keyMap = lib.mkForce "us";

  # claude-code and bws (crann ai-utils/terminal) are unfree, as on blueprint.
  nixpkgs.config.allowUnfree = true;

  crann.desktop = {
    enable = true;
    audio.support32Bit = false;
  };

  # GDM login screen (as on blueprint). Its greeter is a gnome-shell
  # instance, which costs a few hundred MB of RAM and about 1 GB of closure,
  # all from cache.nixos.org. mutter honours the panel's DRM orientation,
  # so the greeter comes up in landscape. greetd + tuigreet was the lighter
  # option it replaced.
  services.displayManager = {
    gdm.enable = true;
    defaultSession = "niri";
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
