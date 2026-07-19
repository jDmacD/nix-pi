{
  inputs,
  ...
}:

{
  imports =[
    inputs.sops-nix.nixosModules.sops
  ];

  sops = {
        defaultSopsFormat = "yaml";
        defaultSopsFile = ../../hosts/secrets.yaml;
      };

}