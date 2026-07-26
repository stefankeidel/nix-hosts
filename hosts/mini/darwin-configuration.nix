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
    nu-extra = {
      file = ../../secrets/nu-extra-env.age;
      path = "/Users/stefan/.extra.nu";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
    gitlab-token = {
      file = ../../secrets/gitlab-token.age;
      path = "/Users/stefan/.config/gitlab-token";
      owner = "stefan";
      group = "staff";
      mode = "600";
    };
  };

  # Let nix-darwin manage Homebrew itself
  homebrew = {
    enable = true;

    # Apple Silicon vs Intel handled automatically
    onActivation = {
      # autoUpdate = true;
      # upgrade = true;
      # cleanup = "zap";
    };

    # Formulae = `brew install`
    # brews = [
    # ];

    # Casks = `brew install --cask`
    casks = [
      "soulseek"
      "musicbrainz-picard"
      "marta"
      "proton-drive"
      "transmission"
    ];

    # Optional: Mac App Store apps
    # masApps = {
    #   Xcode = 497799835;
    # };
  };


  system.stateVersion = 6;# initial nix-darwin state
}
