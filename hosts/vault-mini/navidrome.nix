{ config, lib, pkgs, ... }:

{
  age.secrets.navidrome-env = {
    file = ../../secrets/navidrome.env.age;
    owner = "navidrome";
    group = "navidrome";
    mode = "600";
    path = "/var/lib/navidrome/navidrome.env";
  };

  age.secrets.rclone-navidrome = {
    file = ../../secrets/rclone.conf.age;
    path = "/var/lib/navidrome/.config/rclone/rclone.conf";
    owner = "navidrome";
    mode = "600";
  };

  # mount media from external drive
  fileSystems."/var/lib/navidrome/music" = {
    device = "/mnt/share/Share/Music";
    fsType = "none";
    options = [
      "bind"
      "rw"
      "x-systemd.requires-mounts-for=/mnt/share"
    ];
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;

    environmentFile = "/var/lib/navidrome/navidrome.env"; 

    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/var/lib/navidrome/music/";
      # EnableSharing = true;
      LogLevel = "INFO";
      Scanner.Schedule = "@every 1h";
    };
  };
}
