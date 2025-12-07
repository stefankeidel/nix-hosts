{
  lib,
  modulesPath,
  inputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    # Start out with a minimal config. This disables much of the
    # generated documentation and so on by default, but saves
    # size and bandwidth.
    "${modulesPath}/profiles/minimal.nix"
    inputs.self.nixosModules.vm-base
    inputs.self.nixosModules.vfkit-vz
    inputs.self.nixosModules.host-shared
    inputs.self.nixosModules.actualbudget
  ];

  networking.hostName = "vm-mini";
  networking.firewall.enable = false;

  vmBase = {
    stefanUser.enable = true;
    openssh.enable = true;
    tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      extraUpFlags = [
        "--hostname=vm-mini"
        "--accept-routes"
      ];
    };
  };

  # Set how many  CPU cores and MB of memory to allocate
  # to this VM. Depending on your machine and the amount of VMs
  # you want to run, those might be good to adapt.
  # old rig
  virtualisation = {
    cores = lib.mkDefault 1;
    memorySize = lib.mkDefault (2 * 1024);
    macAddress = "f6:25:e2:48:58:1e";

    # host-side persistence via virtio-fs; guest otherwise stays ephemeral
    sharedDirectories = {
      persistent = {
        source = "/Users/stefan/vms/nextcloud-persistent";
        target = "/var/lib/nextcloud";
        securityModel = "none";
      };
      actualbudget = {
        source = "/Users/stefan/vms/actualbudget-persistent";
        target = "/var/lib/actualbudget";
        securityModel = "none";
      };
    };

    vfkit-vz = {
      enable = true;
      name = config.networking.hostName;
      stdioConsole = false;
    };
  };

  # Enable a password-less root console in initrd if it fails
  # to switch to stage2 for any reason. This severely inpacts
  # security, but makes debugging issues easier. As we are in
  # an VM, defence against attackers with access to the console
  # seems to be point-less anyway.
  boot.initrd.systemd.emergencyAccess = lib.mkDefault true;

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
    hostName = "sync.keidel.me";

    config = {
      dbtype = "sqlite";      # no dbhost/dbuser/dbpass needed
      dbname = "nextcloud";   # SQLite file will be under dataDir (nextcloud.db)
      adminuser = "admin";
      adminpassFile = "/var/lib/nextcloud/nextcloud-admin-pass-file";
    };

    settings.trusted_domains = [
      "keidel.me"
      "vm-mini"
    ];
  };

  services.nginx.virtualHosts."sync.keidel.me" = {
    forceSSL = false;
    enableACME = false;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "1188614+stefankeidel@users.noreply.github.com";
  };

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages.${stdenv.hostPlatform.system}.default
  ];

  # Required for some NixOS modules. See it's description at
  # https://search.nixos.org/options?channel=unstable&show=system.stateVersion
  system.stateVersion = "25.05";
}
