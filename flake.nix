{
  description = "Sharing home-manager modules between nixos and darwin";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    nixpkgs-darwin-pinned.url = "github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";

    # some of my "hosted" systems are on stable :shrug:
    nix-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    stefan-website = {
      type = "github";
      owner = "stefankeidel";
      repo = "website";
      flake = false;
    };

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.home-manager.follows = "home-manager";

    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    authentik-nix.url = "github:nix-community/authentik-nix";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    # Optional, to download less. Neither the module nor the overlay uses this input.
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";
  };

  # Load the blueprint
  outputs =
    inputs:
    let
      blueprintOutputs = inputs.blueprint { inherit inputs; };

      mkPinnedDarwin =
        {
          host,
          user,
        }:
        inputs.nix-darwin.lib.darwinSystem {
          pkgs = import inputs.nixpkgs-darwin-pinned {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
          specialArgs = {
            inherit inputs;
          };
          modules = [
            (./. + "/hosts/${host}/darwin-configuration.nix")
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                };
                users.${user} = import (./. + "/hosts/${host}/users/${user}/home-configuration.nix");
              };
            }
          ];
        };
    in
    blueprintOutputs
    // {
      darwinConfigurations = blueprintOutputs.darwinConfigurations // {
        mini = mkPinnedDarwin {
          host = "mini";
          user = "stefan";
        };
        lichtblick = mkPinnedDarwin {
          host = "lichtblick";
          user = "stefan.keidel@lichtblick.de";
        };
      };
    };
}
