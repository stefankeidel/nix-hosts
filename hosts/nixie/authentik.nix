{config, ...}: {
  age.secrets.authentik-env = {
    file = ../../secrets/authentik.env.age;
    owner = "authentik";
    group = "authentik";
    mode = "600";
  };

  services.authentik = {
    enable = true;
    environmentFile = config.age.secrets.authentik-env.path;

    nginx = {
      enable = true;
      enableACME = true;
      host = "auth.keidel.me";
    };

    settings = {
      disable_startup_analytics = true;
      avatars = "initials";
      redis = {
        host = "127.0.0.1";
        port = 6379;
      };
    };
  };

  services.redis.servers.authentik = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  systemd.services.authentik = {
    requires = [ "redis-authentik.service" ];
    after = [
      "agenix.service"
      "redis-authentik.service"
    ];
  };

  systemd.services.authentik-worker = {
    requires = [ "redis-authentik.service" ];
    after = [
      "agenix.service"
      "redis-authentik.service"
    ];
  };
}
