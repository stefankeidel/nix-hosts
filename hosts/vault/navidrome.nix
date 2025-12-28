{ config, pkgs, ... }:

{
  age.secrets.navidrome-env = {
    file = ../../secrets/navidrome.env.age;
    owner = "navidrome";
    group = "navidrome";
    mode = "600";
    path = "/var/lib/navidrome/navidrome.env";
  };

  # mount storage box
  # this is the old hacky way requiring me to put ssh keys in place by hand
  # 
  # fileSystems."/mnt/storagebox" = {
  #   device = "u440580@u440580.your-storagebox.de:";
  #   fsType = "fuse.sshfs";
  #   options = [
  #     "Identityfile=/var/lib/id_ed25519"
  #     "x-systemd.automount" # mount the filesystem automatically on first access
  #     "allow_other" # don't restrict access to only the user which `mount`s it (because that's probably systemd who mounts it, not you)
  #     "user" # allow manual `mount`ing, as ordinary user.
  #     "_netdev"
  #   ];
  # };
  # boot.supportedFilesystems."fuse.sshfs" = true;
  programs.fuse.userAllowOther = true;

  systemd.services.rclone-hetzner-sb-music = {
    # Ensure the service starts after the network is up
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];

    # Service configuration
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "/run/current-system/sw/bin/mkdir -p /var/lib/navidrome/music"; # Creates folder if didn't exist
      ExecStart = "${pkgs.rclone}/bin/rclone --config /var/lib/navidrome/.config/rclone/rclone.conf mount sb:music /var/lib/navidrome/music --read-only --allow-other"; # Mounts
      ExecStop = "/run/current-system/sw/bin/fusermount -u /var/lib/navidrome/music"; # Dismounts
      Restart = "on-failure";
      RestartSec = "10s";
      User = "navidrome";
      Group = "navidrome";
      Environment = [ "PATH=/run/wrappers/bin/:$PATH" ]; # Required environments
    };
  };

  services.navidrome = {
    enable = true;

    environmentFile = "/var/lib/navidrome/navidrome.env"; 

    settings = {
      # Tailscale only for now
      Address = "100.107.111.21";
      Port = 4533;
      #MusicFolder = "/home/stefan/music/";
      MusicFolder = "/var/lib/navidrome/music/";
      # EnableSharing = true;
      LogLevel = "DEBUG";
      Scanner.Schedule = "@every 1h";
    };
  };
}
