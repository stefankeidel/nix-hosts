{ ... }:
{
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    openFirewall = false;
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

    machine-learning.environment = {
      HF_XET_CACHE = "/var/cache/immich/huggingface-xet";
    };
  };

  users.users.immich = {
    home = "/var/lib/immich";
    createHome = true;
  };

  # Immich uses Redis for cache/queues; avoid failed RDB snapshots blocking writes.
  services.redis.servers.immich.save = [ ];

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
