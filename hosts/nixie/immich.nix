{ ... }:
{
  services.immich = {
    enable = true;
    openFirewall = true;
    mediaLocation = "/mnt/sb/immich";

    settings = {
      backup.database = {
        cronExpression = "0 02 * * *";
        enabled = true;
        keepLastAmount = 14;
      };
      server.externalDomain = "https://images.keidel.me";
      storageTemplate = {
        enabled = true;
        hashVerificationEnabled = true;
        template = "{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}";
      };
    };
  };

  systemd.services.immich-server = {
    requires = [ "rclone-mount-sb.service" ];
    after = [ "rclone-mount-sb.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/sb" ];
  };

  systemd.services.immich-machine-learning = {
    requires = [ "rclone-mount-sb.service" ];
    after = [ "rclone-mount-sb.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/sb" ];
  };
}
