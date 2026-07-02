{ config, ... }:
let
  authentikEnv = config.age.secrets.authentik-env.path;
  image = "ghcr.io/goauthentik/server:2026.5.3";
  commonEnvironment = {
    AUTHENTIK_AVATARS = "initials";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9000";
    AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:9443";
    AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = "127.0.0.0/8,::1/128";
    AUTHENTIK_POSTGRESQL__HOST = "100.96.176.26";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
  };
in
{
  age.secrets.authentik-env = {
    file = ../../secrets/authentik.env.age;
    owner = "root";
    group = "root";
    mode = "600";
  };

  services.postgresql = {
    ensureDatabases = [ "authentik" ];
    ensureUsers = [
      {
        name = "authentik";
        ensureDBOwnership = true;
      }
    ];
  };

  virtualisation.podman.enable = true;

  virtualisation.oci-containers.containers = {
    authentik-server = {
      inherit image;
      cmd = [ "server" ];
      environment = commonEnvironment;
      environmentFiles = [ authentikEnv ];
      extraOptions = [
        "--network=host"
        "--shm-size=512m"
      ];
      volumes = [
        "/var/lib/authentik/data:/data"
        "/var/lib/authentik/templates:/templates"
      ];
    };

    authentik-worker = {
      inherit image;
      cmd = [ "worker" ];
      environment = commonEnvironment;
      environmentFiles = [ authentikEnv ];
      extraOptions = [
        "--network=host"
        "--shm-size=512m"
      ];
      user = "root";
      volumes = [
        "/var/lib/authentik/certs:/certs"
        "/var/lib/authentik/data:/data"
        "/var/lib/authentik/templates:/templates"
      ];
    };
  };

  services.nginx.virtualHosts."auth.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/authentik 0750 root root -"
    "d /var/lib/authentik/certs 0750 root root -"
    "d /var/lib/authentik/data 0750 root root -"
    "d /var/lib/authentik/templates 0750 root root -"
  ];

  systemd.services.podman-authentik-server = {
    requires = [
      "postgresql.target"
    ];
    after = [
      "network-online.target"
      "postgresql.target"
    ];
  };

  systemd.services.podman-authentik-worker = {
    requires = [
      "postgresql.target"
    ];
    after = [
      "network-online.target"
      "postgresql.target"
    ];
  };
}
