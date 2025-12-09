{ config, inputs, lib, pkgs, ... }: {
  imports = [
    inputs.agenix.nixosModules.default
    inputs.comin.nixosModules.comin
    inputs.self.nixosModules.host-shared
    inputs.self.nixosModules.actualbudget
    ./hardware-configuration.nix
    ./networking.nix
  ];

  # boot stuff
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  # networking
  networking.hostName = "vault";
  networking.domain = "";
  networking.useDHCP = true;

  # basic config
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.stefan = {
    isNormalUser = true;
    extraGroups = ["wheel" "podman"];
    openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAwU52M/vXuUkthu481OGKYMzFGwc9GfjvVwDLt7yQGeDXUZHx5tpL2NEKSS3imnTfOJp25wFTOAJdF63eznIOUEc+5dCZe8xeZ7IMASGlNQJy51sNUlx986BIjYxLbCl0tykkySs82ZNaog9BapjxiHm2tXb1LFR2CsGOg9mLqRVNxQkOj8KkX5+r/NhVxQRFFW8OJn7rgqsyJtA7vKRwEP+nUsokO3cr/+sWeW7APgrnnkh9iYr/ZG6ibZH/m1+t4yW1kcENVy2X8Gyrs0GWMYQCLrBB+zJYBdwxBdeWSt76QlZnOpdwWcaZEC5PUVzTiKtyUok2NjBoqdpnLezrDw=='' ];
  };

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

  security.sudo.wheelNeedsPassword = false;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = ["--advertise-exit-node"];
    permitCertUid = "caddy";
  };

  # syncthing
  services.syncthing = {
    enable = true;
    openDefaultPorts = false; # only tailnet
    # Optional: GUI credentials (can be set in the browser instead)
    settings.gui = {
      user = "stefan";
      password = "stefan";
    };

    guiAddress = "0.0.0.0:8384";

    settings.devices = {
      "mini" = { id = "JU7KAPL-2RCNFV4-S4QLXAZ-46R5DZJ-OVO34RS-6MALUQE-5F4L4AA-ZCCZIAJ"; };
      "lichtblick" = { id = "ZOOJ533-GWZLWPA-EPW5AOT-F327BKZ-6DAQRCC-6D5G7PV-C63SGX4-A53R4AS"; };
    };
    settings.folders = {
      "Vault" = {
        path = "/var/lib/syncthing/Vault";
        devices = [ "mini" "lichtblick" ];
      };
    };
  };

  # gitops
  services.comin = {
    enable = true;
    remotes = [{
      name = "origin";
      url = "https://github.com/stefankeidel/nix-hosts.git";
      branches.main.name = "main";
    }];
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    #22 #ssh, for now
    41641 # tailscale
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.optimise.automatic = true;

  system.stateVersion = "25.05";
}
