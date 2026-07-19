{
  perSystem =
    { pkgs, inputs', ... }:
    {
      devShells.default = pkgs.mkShell {
        name = "nix-pi";
        packages = with pkgs; [
          # fleet deployment (see deploy.nix)
          inputs'.deploy-rs.packages.default
          # secrets management (see modules/nixos/sops.nix, .sops.yaml)
          sops
          age
          ssh-to-age
          # disk layout for Pi 5 / CM4 hosts
          disko
          # nix tooling
          nixfmt-rfc-style
          nix-tree
        ];
      };
    };
}
