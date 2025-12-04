# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # the default agenix module
    inputs.agenix.nixosModules.default
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./nextcloud.nix
    ./website.nix
    ./backup.nix
    ./actualbudget.nix
  ];

  # secrets
  age.secrets = {
    rclone = {
      file = ../../secrets/rclone.conf.age;
      path = "/var/lib/nextcloud/.config/rclone/rclone.conf";
      owner = "nextcloud";
      mode = "600";
    };
    restic = {
      file = ../../secrets/restic.age;
      owner = "nextcloud";
      mode = "600";
    };
  };

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only

  networking.hostName = "nixie";
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # in an ideal world, we'd use the below, but not yet
  networking.useDHCP = true;

  # networkd config
  # systemd.network.enable = true;

  # systemd.network.networks."10-wan" = {
  #   matchConfig.Name = "enp1s0:"; # either ens3 or enp1s0 depending on system, check 'ip addr'
  #     networkConfig.DHCP = "ipv4";
  #     address = [
  #       # replace this address with the one assigned to your instance
  #       "2a01:4f8:c013:1160::/64"
  #     ];
  #     routes = [
  #       { Gateway = "fe80::1"; }
  #     ];
  # };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.stefan = {
    isNormalUser = true;
    extraGroups = ["wheel" "podman"];
  };

  # it's just me, so :shrug:
  security.sudo.wheelNeedsPassword = false;

  # yes, flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # gc
  nix.optimise.automatic = true;

  # cachix
  nix.settings.extra-substituters = "https://cache.nixos.org https://nix-community.cachix.org https://sylvorg.cachix.org";
  nix.settings.extra-trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= sylvorg.cachix.org-1:xd1jb7cDkzX+D+Wqt6TemzkJH9u9esXEFu1yaR9p8H8=";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    fuse
    git
    htop
    mosh
    rclone
    restic
    ripgrep
    rsync
    screen
    speedtest-go
    tailscale
    vim
    vnstat
    wget
    inputs.agenix.packages.${stdenv.hostPlatform.system}.default
  ];

  # postgres
  services.postgresql = {
    enable = true;
    ensureDatabases = ["accounting"];
    enableTCPIP = true;
    authentication = pkgs.lib.mkOverride 10 ''
      #...
      #type database DBuser origin-address auth-method
      local all       all     trust
      # ipv4
      host  all      all     127.0.0.1/32   trust
      # ipv6
      host all       all     ::1/128        trust
      # tailscale net
      host  all      all     100.0.0.0/8    trust
    '';
    initialScript = pkgs.writeText "backend-initScript" ''
      CREATE ROLE postgres WITH LOGIN PASSWORD 'unicorn' CREATEDB;
      CREATE DATABASE accounting;
      GRANT ALL PRIVILEGES ON DATABASE accounting TO postgres;
    '';

    # listen only locally and on tailscale. No interneterino
    settings.port = 5432;
    settings.listen_addresses = lib.mkForce "100.96.176.26";
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    ports = [22];
    openFirewall = false; # only via VPN/Wireguard/Tailscale
    settings = {
      PasswordAuthentication = false;
      AllowUsers = ["stefan"];
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "yes";
    };
  };

  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraSetFlags = ["--advertise-exit-node"];

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    80 # http
    443 # https
    41641 # tailscale
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # some generic webserver config
  services.nginx.enable = true;

  security.acme = {
    acceptTerms = true;
    defaults.email = "1188614+stefankeidel@users.noreply.github.com";
  };

  # metabase
  # services.metabase = {
  #   enable = true;
  #   openFirewall = true;
  #   listen.ip = "100.96.176.26";
  # };

  # mount storage box
  # fileSystems."/mnt/storagebox" = {
  #   device = "u440580@u440580.your-storagebox.de:/nixie";
  #   fsType = "fuse.sshfs";
  #   options = [
  #     "Identityfile=/var/bak/id_ed25519"
  #     "x-systemd.automount" # mount the filesystem automatically on first access
  #     "allow_other" # don't restrict access to only the user which `mount`s it (because that's probably systemd who mounts it, not you)
  #     "user" # allow manual `mount`ing, as ordinary user.
  #     "_netdev"
  #   ];
  # };
  # boot.supportedFilesystems."fuse.sshfs" = true;

  programs.fuse.userAllowOther = true;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?
}
