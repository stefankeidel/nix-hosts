{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.self.nixosModules.host-shared
    inputs.self.darwinModules.desktop
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mini";

  nix.settings.trusted-users = ["root" "stefan"];

  system.primaryUser = "stefan";

  users.users."stefan" = {
    home = "/Users/stefan";
  };

  system.stateVersion = 6; # initial nix-darwin state
}
