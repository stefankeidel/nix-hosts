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

  age.secrets = {
    rclone = {
      file = ../../secrets/rclone.conf.age;
      path = "/Users/stefan.keidel@lichtblick.de/.config/rclone/rclone.conf";
      owner = "stefan.keidel@lichtblick.de";
      group = "staff";
      mode = "600";
    };
    restic = {
      file = ../../secrets/restic.age;
      path = "/Users/stefan.keidel@lichtblick.de/.config/restic-pw";
      owner = "stefan.keidel@lichtblick.de";
      group = "staff";
      mode = "600";
    };
    pgpass = {
      file = ../../secrets/pgpass.age;
      path = "/Users/stefan.keidel@lichtblick.de/.pgpass";
      owner = "stefan.keidel@lichtblick.de";
      group = "staff";
      mode = "600";
    };
    authinfo = {
      file = ../../secrets/authinfo.age;
      path = "/Users/stefan.keidel@lichtblick.de/.authinfo";
      owner = "stefan.keidel@lichtblick.de";
      group = "staff";
      mode = "600";
    };
    zsh-extra = {
      file = ../../secrets/zsh-extra.age;
      path = "/Users/stefan.keidel@lichtblick.de/.extra";
      owner = "stefan.keidel@lichtblick.de";
      group = "staff";
      mode = "600";
    };
  };

  system.stateVersion = 6; # initial nix-darwin state
}
