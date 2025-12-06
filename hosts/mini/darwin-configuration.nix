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

  age.secrets = {
    rclone = {
      file = ../../secrets/rclone.conf.age;
      path = "/Users/stefan/.config/rclone/rclone.conf";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    restic = {
      file = ../../secrets/restic.age;
      path = "/Users/stefan/.config/restic-pw";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    hcloud_token = {
      file = ../../secrets/hcloud_token.age;
      path = "/Users/stefan/.config/hcloud_token";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    pgpass = {
      file = ../../secrets/pgpass.age;
      path = "/Users/stefan/.pgpass";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    authinfo = {
      file = ../../secrets/authinfo.age;
      path = "/Users/stefan/.authinfo";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    tailscale_auth = {
      file = ../../secrets/tailscale-authkey.age;
      path = "/Users/stefan/vms/secrets/tailscale-authkey";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
  };

  system.stateVersion = 6;# initial nix-darwin state
}
