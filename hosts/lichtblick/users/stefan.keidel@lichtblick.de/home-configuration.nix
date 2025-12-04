{ pkgs, inputs, ... }:
{

  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.home-darwin
  ];
}
