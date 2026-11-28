{
  flake,
  inputs,
  hostName,
  system ? "aarch64-darwin",
  configuration,
  users,
}: {
  class = "nix-darwin";

  value = inputs.nix-darwin-stable.lib.darwinSystem {
    # Home Manager loads the portable services helper from the package set.
    lib = inputs.nix-stable.lib.extend (_: _: {
      inherit (inputs.nixpkgs-darwin.lib) importService;
    });
    specialArgs = { inherit flake inputs hostName; };
    modules = [
      configuration
      inputs.home-manager-stable.darwinModules.default
      {
        # Keep nix-darwin's evaluation library on 26.05, but install packages from 26.11.
        nixpkgs.source = inputs.nixpkgs-darwin;
        nixpkgs.flake.source = inputs.nixpkgs-darwin.outPath;
        nixpkgs.hostPlatform = inputs.nixpkgs-darwin.lib.systems.elaborate system;

        # The uninstaller must evaluate against the matching 26.05 package set.
        system.tools.darwin-uninstaller.enable = false;
        environment.systemPackages = [
          inputs.nix-darwin-stable.packages.${system}.darwin-uninstaller
        ];

        home-manager = {
          inherit users;
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit flake inputs; };
        };
      }
    ];
  };
}
