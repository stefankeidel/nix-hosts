{
  description = "Sharing home-manager modules between nixos and darwin";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    # Stable package set for nixie and mini.
    nix-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager-stable.url = "github:nix-community/home-manager/release-26.05";
    home-manager-stable.inputs.nixpkgs.follows = "nix-stable";

    nix-darwin-stable.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin-stable.inputs.nixpkgs.follows = "nix-stable";

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

    agenix.url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "nix-darwin";
    agenix.inputs.home-manager.follows = "home-manager";

    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    # Optional, to download less. Neither the module nor the overlay uses this input.
    nix-doom-emacs-unstraightened.inputs.nixpkgs.follows = "";

    # pi coding agent
    pi.url = "github:lukasl-dev/pi.nix";

    pi-memory = {
      url = "github:jayzeng/pi-memory";
      flake = false;
    };

    pi-observational-memory = {
      url = "github:elpapi42/pi-observational-memory";
      flake = false;
    };

    pi-web-access = {
      url = "github:nicobailon/pi-web-access";
      flake = false;
    };

    pi-provider-litellm = {
      url = "github:balcsida/pi-provider-litellm";
      flake = false;
    };

    pi-subagents = {
      url = "github:nicobailon/pi-subagents";
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
  outputs = inputs: inputs.blueprint { inherit inputs; };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://pi.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
