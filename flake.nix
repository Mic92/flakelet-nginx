{
  description = "nginx provider implementing the flakelet http/v1 contract";

  outputs =
    { self }:
    {
      nixosModules.provider = ./modules/provider.nix;
      nixosModules.default = self.nixosModules.provider;
    };
}
