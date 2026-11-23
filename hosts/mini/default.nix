{
  flake,
  inputs,
  hostName,
}: {
  class = "nix-darwin";

  value = inputs.nix-darwin-stable.lib.darwinSystem {
    specialArgs = { inherit flake inputs hostName; };
    modules = [
      ./darwin-configuration.nix
      inputs.home-manager-stable.darwinModules.default
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit flake inputs; };
          users.stefan = import ./users/stefan/home-configuration.nix;
        };
      }
    ];
  };
}
