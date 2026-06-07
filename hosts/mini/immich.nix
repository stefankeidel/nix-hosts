{
  pkgs,
  ...
}:
let
  user = "stefan";
  stateDir = "/Users/${user}/Immich";
  uploadLocation = "/Volumes/SAM/Share/Immich";
  immichVersion = "v2.7.5";

  immichConfig = pkgs.writeText "immich.json" (
    builtins.toJSON {
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
    }
  );

  composeFile = pkgs.writeText "immich-compose.yml" ''
    name: immich

    services:
      immich-server:
        container_name: immich_server
        image: ghcr.io/immich-app/immich-server:''${IMMICH_VERSION:-v2}
        volumes:
          - ''${UPLOAD_LOCATION}:/data
          - ''${CONFIG_LOCATION}:''${IMMICH_CONFIG_FILE}:ro
          - /etc/localtime:/etc/localtime:ro
        env_file:
          - ''${ENV_FILE}
        ports:
          - "0.0.0.0:2283:2283"
        depends_on:
          - redis
          - database
        restart: always
        healthcheck:
          disable: false

      immich-machine-learning:
        container_name: immich_machine_learning
        image: ghcr.io/immich-app/immich-machine-learning:''${IMMICH_VERSION:-v2}
        volumes:
          - ''${MODEL_CACHE_LOCATION}:/cache
        env_file:
          - ''${ENV_FILE}
        restart: always
        healthcheck:
          disable: false

      redis:
        container_name: immich_redis
        image: docker.io/valkey/valkey:9@sha256:4963247afc4cd33c7d3b2d2816b9f7f8eeebab148d29056c2ca4d7cbc966f2d9
        healthcheck:
          test: redis-cli ping || exit 1
        restart: always

      database:
        container_name: immich_postgres
        image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
        environment:
          POSTGRES_PASSWORD: ''${DB_PASSWORD}
          POSTGRES_USER: ''${DB_USERNAME}
          POSTGRES_DB: ''${DB_DATABASE_NAME}
          POSTGRES_INITDB_ARGS: "--data-checksums"
        volumes:
          - ''${DB_DATA_LOCATION}:/var/lib/postgresql/data
        shm_size: 128mb
        restart: always
        healthcheck:
          disable: false
  '';
in
{
  environment.systemPackages = with pkgs; [
    colima
    docker-client
    docker-compose
  ];

  launchd.user.agents.immich = {
    path = with pkgs; [
      colima
      coreutils
      docker-client
      docker-compose
      gnugrep
      openssl
    ];

    script = ''
      set -euo pipefail

      export HOME=/Users/${user}

      state_dir=${stateDir}
      upload_location=${uploadLocation}
      env_file=$state_dir/.env
      password_file=$state_dir/db-password
      config_location=$state_dir/config/immich.json
      colima_profile=immich

      mkdir -p \
        "$state_dir/config" \
        "$state_dir/model-cache" \
        "$state_dir/postgres" \
        "$upload_location"

      if [ ! -f "$password_file" ]; then
        umask 077
        openssl rand -hex 24 > "$password_file"
      fi

      install -m 0644 ${immichConfig} "$config_location"

      cat > "$env_file" <<EOF
      UPLOAD_LOCATION=$upload_location
      DB_DATA_LOCATION=$state_dir/postgres
      IMMICH_VERSION=${immichVersion}
      DB_PASSWORD=$(cat "$password_file")
      DB_USERNAME=postgres
      DB_DATABASE_NAME=immich
      IMMICH_CONFIG_FILE=/config/immich.json
      CONFIG_LOCATION=$config_location
      MODEL_CACHE_LOCATION=$state_dir/model-cache
      ENV_FILE=$env_file
      TZ=Europe/Berlin
      EOF
      chmod 0600 "$env_file"

      if ! colima status --profile "$colima_profile" >/dev/null 2>&1; then
        colima start \
          --profile "$colima_profile" \
          --cpu 4 \
          --memory 12 \
          --disk 80 \
          --vm-type vz \
          --mount-type virtiofs \
          --mount "$HOME:w" \
          --mount "/Volumes/SAM:w"
      fi

      export DOCKER_HOST=unix://$HOME/.colima/$colima_profile/docker.sock
      docker-compose --env-file "$env_file" -f ${composeFile} up -d
    '';

    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "/tmp/immich-launchd.log";
      StandardErrorPath = "/tmp/immich-launchd.err";
    };
  };
}
