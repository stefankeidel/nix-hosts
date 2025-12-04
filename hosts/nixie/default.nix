{ flake, inputs, ... }:
{
  class = "nixos";

  value = inputs.nix-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ./configuration.nix
      ];
  };
}
