{
  description = "Sharing home-manager modules between nixos and darwin";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    # some of my "hosted" systems are on stable :shrug:
    nix-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

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

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    # Optional, to download less. Neither the module nor the overlay uses this input.
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";

    # pi coding agent
    pi.url = "github:lukasl-dev/pi.nix";

    pi-rtk-optimizer = {
      url = "github:MasuRii/pi-rtk-optimizer";
      flake = false;
    };

    pi-memory = {
      url = "github:jayzeng/pi-memory";
      flake = false;
    };

    pi-gitlab = {
      url = "github:stefankeidel/pi-gitlab";
      flake = false;
    };

    pi-confluence = {
      url = "github:stefankeidel/pi-confluence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Load the blueprint
  outputs =
    inputs:
    let
      blueprintOutputs = inputs.blueprint { inherit inputs; };

      mkDarwin =
        {
          host,
          user,
        }:
        inputs.nix-darwin.lib.darwinSystem {
          pkgs = import inputs.nixpkgs {
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
        mini = mkDarwin {
          host = "mini";
          user = "stefan";
        };
        lichtblick = mkDarwin {
          host = "lichtblick";
          user = "stefan.keidel@lichtblick.de";
        };
      };
    };

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://pi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
