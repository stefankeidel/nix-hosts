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

  networking.hostName = "Stefan-Keidel-MacBook-Pro";

  nix.settings.trusted-users = ["root" "stefan.keidel@lichtblick.de"];

  system.primaryUser = "stefan.keidel@lichtblick.de";

  users.users."stefan.keidel@lichtblick.de" = {
    home = "/Users/stefan.keidel@lichtblick.de";
  };

  system.stateVersion = 6; # initial nix-darwin state
}
