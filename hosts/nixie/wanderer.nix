{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/wanderer";
  mediaDir = "/mnt/sb/wanderer";
  # Pin the mounted filesystem in each service's namespace, and stop/restart
  # storage users with rclone rather than exposing the bare mount directory.
  mountDependencies = {
    bindsTo = [ "rclone-mount-sb.service" ];
    partOf = [ "rclone-mount-sb.service" ];
    after = [ "rclone-mount-sb.service" ];
    unitConfig.AssertPathIsMountPoint = "/mnt/sb";
    serviceConfig.BindPaths = [ "/mnt/sb" ];
  };
  commonEnvironment = {
    MEILI_URL = "http://wanderer-search:7700";
    ORIGIN = "https://trails.keidel.me";
  };
  commonContainer = {
    networks = [ "wanderer" ];
    environmentFiles = [ "${stateDir}/search.env" ];
  };
  # OCI dependsOn orders startup; wait for readiness before dependents start.
  readinessServices =
    lib.mapAttrs'
      (
        name: healthCommand:
        lib.nameValuePair "podman-wanderer-${name}" (
          lib.mkMerge [
            (lib.optionalAttrs (name != "search") mountDependencies)
            {
              requires = [ "wanderer-init.service" ];
              after = [ "wanderer-init.service" ];
              serviceConfig.ExecStartPost = pkgs.writeShellScript "wanderer-${name}-ready" ''
                for attempt in {1..90}; do
                  if ${pkgs.podman}/bin/podman exec wanderer-${name} ${healthCommand}; then
                    exit 0
                  fi
                  sleep 2
                done
                exit 1
              '';
            }
          ]
        )
      )
      {
        search = "curl --fail --max-time 5 http://localhost:7700/health";
        db = "/curl --fail --max-time 5 http://localhost:8090/health";
        web = "curl --fail --max-time 5 http://localhost:3000/";
      };
in
{
  # Back up both stateDir (including encryption keys) and mediaDir.
  # See wanderer.md for migration steps before deploying this storage split.
  # Secrets are generated once on the host, never placed in the Nix store.
  systemd.services = {
    wanderer-init = lib.mkMerge [
      mountDependencies
      {
        description = "Prepare Wanderer storage, secrets and container network";
        before = [
          "podman-wanderer-search.service"
          "podman-wanderer-db.service"
          "podman-wanderer-web.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "wanderer";
          StateDirectoryMode = "0700";
          UMask = "0077";
        };
        path = [
          pkgs.podman
          pkgs.openssl
        ];
        script = ''
          mkdir -p ${stateDir}/{meili_data,pb_data/storage,plugins}
          mkdir -p ${mediaDir}/{storage,uploads}
          if [ ! -e ${stateDir}/search.env ]; then
            printf 'MEILI_MASTER_KEY=%s\n' "$(openssl rand -hex 32)" > ${stateDir}/search.env.tmp
            mv ${stateDir}/search.env.tmp ${stateDir}/search.env
          fi
          if [ ! -e ${stateDir}/db.env ]; then
            printf 'POCKETBASE_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 16)" > ${stateDir}/db.env.tmp
            mv ${stateDir}/db.env.tmp ${stateDir}/db.env
          fi
          podman network exists wanderer || podman network create wanderer
        '';
      }
    ];
  }
  // readinessServices;

  virtualisation.oci-containers.containers = {
    wanderer-search = commonContainer // {
      image = "docker.io/getmeili/meilisearch:v1.36.0";
      environment = {
        MEILI_NO_ANALYTICS = "true";
        MEILI_ENV = "production";
      };
      volumes = [ "${stateDir}/meili_data:/meili_data" ];
    };

    wanderer-db = commonContainer // {
      image = "docker.io/flomp/wanderer-db:v0.20.0";
      dependsOn = [ "wanderer-search" ];
      environment = commonEnvironment;
      environmentFiles = commonContainer.environmentFiles ++ [ "${stateDir}/db.env" ];
      volumes = [
        "${stateDir}/pb_data:/pb_data"
        "${mediaDir}/storage:/pb_data/storage"
        "${stateDir}/plugins:/data/plugins"
      ];
    };

    wanderer-web = commonContainer // {
      image = "docker.io/flomp/wanderer-web:v0.20.0";
      dependsOn = [
        "wanderer-search"
        "wanderer-db"
      ];
      environment = commonEnvironment // {
        PUBLIC_POCKETBASE_URL = "http://wanderer-db:8090";
        PUBLIC_DISABLE_SIGNUP = "true";
        PUBLIC_PRIVATE_INSTANCE = "true";
        BODY_SIZE_LIMIT = "104857600";
        UPLOAD_FOLDER = "/app/uploads";
        OVERPASS_API_URL = "https://overpass-api.de";
        VALHALLA_URL = "https://valhalla1.openstreetmap.de";
        NOMINATIM_URL = "https://nominatim.openstreetmap.org";
        PUBLIC_MAP_MAX_POLYLINES = "100";
      };
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [ "${mediaDir}/uploads:/app/uploads" ];
    };
  };

  services.nginx.virtualHosts."trails.keidel.me" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = "client_max_body_size 100m;";

    # Temporarily rely on Wanderer's own login rather than Authelia.
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Original-URL $scheme://$host$request_uri;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-URI $request_uri;
      '';
    };
  };
}
