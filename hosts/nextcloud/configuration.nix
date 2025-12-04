{
  flake,
  lib,
  modulesPath,
  inputs,
  ...
}: {
  imports = [
    # Start out with a minimal config. This disables much of the
    # generated documentation and so on by default, but saves
    # size and bandwidth.
    "${modulesPath}/profiles/minimal.nix"
    flake.modules.nixos.vfkit-vm
    #flake.modules.nixos.vm-base
    inputs.self.nixosModules.host-shared
  ];

  nixpkgs.hostPlatform.system = "aarch64-linux";

  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "server";

  users.users.stefan = {
    isNormalUser = true;
    extraGroups = ["wheel" "podman"];

    openssh.authorizedKeys.keys = [''ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAwU52M/vXuUkthu481OGKYMzFGwc9GfjvVwDLt7yQGeDXUZHx5tpL2NEKSS3imnTfOJp25wFTOAJdF63eznIOUEc+5dCZe8xeZ7IMASGlNQJy51sNUlx986BIjYxLbCl0tykkySs82ZNaog9BapjxiHm2tXb1LFR2CsGOg9mLqRVNxQkOj8KkX5+r/NhVxQRFFW8OJn7rgqsyJtA7vKRwEP+nUsokO3cr/+sWeW7APgrnnkh9iYr/ZG6ibZH/m1+t4yW1kcENVy2X8Gyrs0GWMYQCLrBB+zJYBdwxBdeWSt76QlZnOpdwWcaZEC5PUVzTiKtyUok2NjBoqdpnLezrDw=='' ];
  };

  # it's just me :shrug:
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      StrictModes = false;
      PasswordAuthentication = false;
    };
  };

  # Set how many  CPU cores and MB of memory to allocate
  # to this VM. Depending on your machine and the amount of VMs
  # you want to run, those might be good to adapt.
  # old rig
  # virtualisation = {
  #   cores = lib.mkDefault 1;
  #   memorySize = lib.mkDefault (2 * 1024);
  #   macAddress = "f6:25:e2:48:58:1e";
  #   sharedDirectories = {
  #     persistent = {
  #       source = ''"$PWD/persistent"'';
  #       target = "/persistent";
  #     };
  #   };
  # };

  # chatgpt module
  virtualisation.vfkit = {
    enable = true;
    name = "nixos-vm";
    memoryMB = 4096;
    cpus = 2;
    diskImagePath = /Users/stefan/nixos-root.qcow2; # existing qcow2
    macAddress = "52:54:00:12:34:56";                   # locally administered MAC
    networking.mode = "bridged";                        # own IP via DHCP
    #networking.interface = "en0";                       # optional; macOS device to bridge
  };


  # Set a static MAC address to get the same IP every time.
  # This is an optional, non-upstream option defined in this repo.
  services.getty.autologinUser = lib.mkDefault "stefan";

  # Enable a password-less root console in initrd if it fails
  # to switch to stage2 for any reason. This severely inpacts
  # security, but makes debugging issues easier. As we are in
  # an VM, defence against attackers with access to the console
  # seems to be point-less anyway.
  boot.initrd.systemd.emergencyAccess = lib.mkDefault true;

  # Required for some NixOS modules. See it's description at
  # https://search.nixos.org/options?channel=unstable&show=system.stateVersion
  system.stateVersion = "25.05";
}
