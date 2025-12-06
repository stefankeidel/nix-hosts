{
  flake,
  inputs,
  ...
}: {
  class = "nixos";

  value = inputs.nix-stable.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = {
      inherit inputs;
    };
    modules = [
      ./configuration.nix
    ];
  };
}
