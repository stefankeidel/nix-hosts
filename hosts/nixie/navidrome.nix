{ ... }:
{
  age.secrets.navidrome-env = {
    file = ../../secrets/navidrome.env.age;
    owner = "navidrome";
    group = "navidrome";
    mode = "600";
    path = "/var/lib/navidrome/navidrome.env";
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;

    environmentFile = "/var/lib/navidrome/navidrome.env";

    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/mnt/sb/music";
      LogLevel = "INFO";
      Scanner.Schedule = "@every 1h";
    };
  };

  systemd.services.navidrome = {
    requires = [ "rclone-mount-sb.service" ];
    after = [ "rclone-mount-sb.service" ];
  };
}
