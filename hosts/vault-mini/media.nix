{ config, lib, pkgs, ... }:

{
  virtualisation.oci-containers = {
    containers.sabnzbd = {
      image = "lscr.io/linuxserver/sabnzbd:latest";

      ports = [
        "8080:8080"
      ];

      volumes = [
        "/var/lib/sabnzbd/config:/config"
        "/var/lib/sabnzbd/incomplete:/incomplete-downloads"
        "/var/lib/sabnzbd/downloads:/downloads"
      ];
    };
  };

  # services.lidarr = {
  #   enable = true;
  # };

  fileSystems."/var/lib/sabnzbd/downloads" = {
    device = "/mnt/share/Share/Downloads";
    fsType = "none";
    options = [
      "bind"
      "rw"
      "x-systemd.requires-mounts-for=/mnt/share"
    ];
  };
}
