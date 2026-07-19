{
  pkgs,
  ...
}:
let
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMuy91cezuJiIsnk03VC+Ar4ctYsp4SDstd85MZW+GkP James@nixos-surface"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWTHfYsPAZJfT7bTN8gepV31tJU+J7vAJgLcZs46MiV jmacdonald@lwh-hotapril"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC+2xlDod7NmSzxWneuwYPx6BRjTaGc227MhPbNY9DRx"
  ];
in
{

  users.users.jmacdonald = {
    shell = pkgs.bash;
    isNormalUser = true;
    description = "James MacDonald";
    openssh.authorizedKeys.keys = authorizedKeys;
    initialPassword = "password";
    extraGroups = [
      "networkmanager"
      "wheel"
      "audio"
      "sound"
      "video"
    ];
    packages = [ ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "jmacdonald" ];
}
