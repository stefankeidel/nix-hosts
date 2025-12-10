{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.self.nixosModules.host-shared
    inputs.self.darwinModules.desktop
    #inputs.self.darwinModules.vfkit-vms
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "mini";

  nix.settings.trusted-users = ["root" "stefan"];

  system.primaryUser = "stefan";

  users.users."stefan" = {
    home = "/Users/stefan";
  };

  # virtualisation.vfkit-vms = {
  #   enable = true;
  #   instances.vm-mini = {
  #     host = "vm-mini";
  #     runAtLoad = false;
  #     keepAlive = false;
  #     workDir = "/Users/stefan/vms/vfkit-mini";
  #   };
  # };

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
    zsh-extra = {
      file = ../../secrets/zsh-extra.age;
      path = "/Users/stefan/.extra";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
  };

  system.stateVersion = 6;# initial nix-darwin state
}
