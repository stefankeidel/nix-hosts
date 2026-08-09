{
  description = "Sharing home-manager modules between nixos and darwin";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    nixpkgs-darwin-pinned.url = "github:NixOS/nixpkgs?ref=nixos-unstable"; #"github:NixOS/nixpkgs/567a49d1913ce81ac6e9582e3553dd90a955875f";

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
      url = "github:MasuRii/pi-rtk-optimizer/v0.9.0";
      flake = false;
    };

    pi-subagents = {
      url = "github:nicobailon/pi-subagents/7229707ba8232113203d4fb4feded8b71d9dc2f5";
      flake = false;
    };

    pi-memory = {
      url = "github:jayzeng/pi-memory/6b31b462a7b7f8e5c99134166471e090101280b1";
      flake = false;
    };
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
