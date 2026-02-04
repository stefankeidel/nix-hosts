{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # our shared stuff
   # inputs.self.nixosModules.host-shared
    inputs.microvm.nixosModules.microvm
  ];

  networking.hostName = "my-microvm";
  users.users.root.password = "";
  #system.stateVersion = lib.trivial.release;

  # services.getty.autologinUser = "user";
  # users.users.user = {
  #   password = "";
  #   group = "user";
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" "video" ];
  # };
  # users.groups.user = {};
  # security.sudo = {
  #   enable = true;
  #   wheelNeedsPassword = false;
  # };

  microvm = {
    # vcpu = 2;
    # mem = 2048;

    # shares = [{
    #   source = "/nix/store";
    #   mountPoint = "/nix/.ro-store";
    #   tag = "ro-store";
    #   proto = "virtiofs";
    # }];

    # interfaces = [{
    #    type = "user";
    #    id = "usernet";
    #    mac = "02:00:00:01:01:01";
    # }];

    # socket = "rosetta-vm.sock";
    # graphics.enable = true;

    # volumes = [ {
    #   mountPoint = "/var";
    #   image = "var.img";
    #   size = 256;
    # } ];

    # shares = [ {
    #   # use proto = "virtiofs" for MicroVMs that are started by systemd
    #   proto = "9p";
    #   tag = "ro-store";
    #   # a host's /nix/store will be picked up so that no
    #   # squashfs/erofs will be built for it.
    #   source = "/nix/store";
    #   mountPoint = "/nix/.ro-store";
    # } ];

    hypervisor = "qemu";
  };
}
