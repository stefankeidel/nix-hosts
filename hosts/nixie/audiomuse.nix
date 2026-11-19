{ config, lib, pkgs, ... }:
let
  stateDir = "/var/lib/audiomuse";
  image = "ghcr.io/neptunehub/audiomuse-ai:3.7.2";
  commonContainer = {
    networks = [ "audiomuse" ];
    environmentFiles = [ "${stateDir}/postgres.env" ];
  };
  appContainer = serviceType: commonContainer // {
    inherit image;
    dependsOn = [ "audiomuse-postgres" ];
    environment = {
      SERVICE_TYPE = serviceType;
      TZ = config.time.timeZone;
      POSTGRES_USER = "audiomuse";
      POSTGRES_DB = "audiomusedb";
      POSTGRES_HOST = "audiomuse-postgres";
      POSTGRES_PORT = "5432";
      TEMP_DIR = "/app/temp_audio";
    };
    volumes = [
      "${stateDir}/${serviceType}/temp_audio:/app/temp_audio"
      "${stateDir}/${serviceType}/plugins:/app/plugin/installed"
      "${stateDir}/${serviceType}/ivf_cache:/app/ivf_cache"
    ];
  };
in
{
  systemd.services = lib.mkMerge [ {
    audiomuse-init = {
      description = "Prepare AudioMuse-AI storage, database password and network";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "audiomuse";
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
      path = [ pkgs.podman pkgs.openssl ];
      script = ''
        mkdir -p ${stateDir}/{postgres,flask/{temp_audio,plugins,ivf_cache},worker/{temp_audio,plugins,ivf_cache}}
        if [ ! -e ${stateDir}/postgres.env ]; then
          printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)" > ${stateDir}/postgres.env.tmp
          mv ${stateDir}/postgres.env.tmp ${stateDir}/postgres.env
        fi
        podman network exists audiomuse || podman network create audiomuse
      '';
    };
    podman-audiomuse-postgres.serviceConfig.ExecStartPost = pkgs.writeShellScript "audiomuse-postgres-ready" ''
      for attempt in {1..90}; do
        if ${pkgs.podman}/bin/podman exec audiomuse-postgres \
          pg_isready -h 127.0.0.1 -U audiomuse -d audiomusedb; then
          exit 0
        fi
        sleep 2
      done
      exit 1
    '';
  } (lib.genAttrs
    [ "podman-audiomuse-postgres" "podman-audiomuse-flask" "podman-audiomuse-worker" ]
    (_: {
      requires = [ "audiomuse-init.service" ];
      after = [ "audiomuse-init.service" ];
      serviceConfig.UMask = "0077";
    })) ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      # Keep the supported PostgreSQL major version isolated from nixie's host DB.
      audiomuse-postgres = commonContainer // {
        image = "docker.io/library/postgres:15-alpine";
        environment = {
          TZ = config.time.timeZone;
          POSTGRES_USER = "audiomuse";
          POSTGRES_DB = "audiomusedb";
        };
        volumes = [ "${stateDir}/postgres:/var/lib/postgresql/data" ];
      };
      audiomuse-flask = appContainer "flask" // {
        # Navidrome uses the local API; all remote UI/API access goes via Authelia.
        ports = [ "127.0.0.1:8000:8000" ];
      };
      audiomuse-worker = appContainer "worker";
    };
  };

  services.nginx.virtualHosts."audiomuse.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."= /internal/authelia/authz" = {
      proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Connection "";
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$host$request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
      '';
    };

    locations."/" = {
      proxyPass = "http://127.0.0.1:8000";
      proxyWebsockets = true;
      extraConfig = ''
        auth_request /internal/authelia/authz;
        auth_request_set $redirection_url $upstream_http_location;
        error_page 401 =302 $redirection_url;

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_read_timeout 300s;
        client_max_body_size 100m;
      '';
    };
  };
}
