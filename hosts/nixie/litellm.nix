{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/litellm";
  # Match the working local stack; upgrade deliberately, including DB migrations.
  image = "ghcr.io/berriai/litellm:v1.107.0-dev.1";
  uid = "65532";
  gid = "65532";
  providerEnvironment = {
    CHATGPT_TOKEN_DIR = "${stateDir}/chatgpt";
    GITHUB_COPILOT_TOKEN_DIR = "${stateDir}/github-copilot";
    GITHUB_COPILOT_DEVICE_CODE_URL = "https://lichtblick-se.ghe.com/login/device/code";
    GITHUB_COPILOT_ACCESS_TOKEN_URL = "https://lichtblick-se.ghe.com/login/oauth/access_token";
    GITHUB_COPILOT_API_KEY_URL = "https://lichtblick-se.ghe.com/api/v3/copilot_internal/v2/token";
    HOME = stateDir;
    XDG_CACHE_HOME = "${stateDir}/cache";
    DO_NOT_TRACK = "True";
  };
  proxyConfig = (pkgs.formats.yaml { }).generate "litellm.yaml" {
    model_list = [
      {
        model_name = "chatgpt/*";
        litellm_params.model = "chatgpt/*";
      }
      {
        model_name = "github_copilot/*";
        litellm_params.model = "github_copilot/*";
      }
    ];
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
      # Named proxy-admin accounts only; keep the master key for API access.
      disable_env_credential_login = true;
      database_url = "os.environ/DATABASE_URL";
      store_model_in_db = true;
      store_prompts_in_spend_logs = true;
    };
  };
  login = pkgs.writeShellApplication {
    name = "litellm-login";
    runtimeInputs = [
      pkgs.podman
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      if [ "$EUID" -ne 0 ]; then
        echo 'Run with sudo: litellm-login {chatgpt|github-copilot}' >&2
        exit 1
      fi
      case "''${1:-}" in
        chatgpt) module=chatgpt ;;
        github-copilot) module=github_copilot ;;
        *) echo 'Usage: litellm-login {chatgpt|github-copilot}' >&2; exit 2 ;;
      esac
      # Never race a proxy worker refreshing the same OAuth token files.
      exec 9>/run/lock/litellm-login.lock
      flock -n 9
      systemctl start litellm-init.service
      systemctl stop podman-litellm.service
      trap 'systemctl start podman-litellm.service' EXIT
      podman run --rm --interactive --tty --pull=missing \
        --name litellm-login --user ${uid}:${gid} --userns=host \
        --cap-drop=ALL --security-opt=no-new-privileges \
        ${
          lib.concatStringsSep " \\\n        " (
            lib.mapAttrsToList (
              name: value: "--env ${lib.escapeShellArg "${name}=${value}"}"
            ) providerEnvironment
          )
        } \
        --volume ${stateDir}:${stateDir} \
        --entrypoint python ${image} -c \
        "from litellm.llms.$module.authenticator import Authenticator; Authenticator().get_access_token(); print('Login saved.')"
    '';
  };
in
{
  # Stable host/container identity is needed for PostgreSQL peer authentication.
  users.groups.litellm.gid = lib.toInt gid;
  users.users.litellm = {
    isSystemUser = true;
    uid = lib.toInt uid;
    group = "litellm";
    home = stateDir;
  };

  services.postgresql = {
    ensureDatabases = [ "litellm" ];
    ensureUsers = [
      {
        name = "litellm";
        ensureDBOwnership = true;
      }
    ];
    # configuration.nix has a priority-10 HBA override. Insert these before its
    # legacy trust rules, without changing access for existing applications.
    authentication = lib.mkOverride 10 (
      lib.mkBefore ''
        local litellm litellm peer
        local all litellm reject
        local litellm all reject
        host all litellm 0.0.0.0/0 reject
        host all litellm ::/0 reject
        host litellm all 0.0.0.0/0 reject
        host litellm all ::/0 reject
      ''
    );
  };

  systemd.services.litellm-init = {
    description = "Prepare private LiteLLM state and persistent proxy keys";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "litellm";
      Group = "litellm";
      StateDirectory = "litellm";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    path = [ pkgs.openssl ];
    script = ''
      mkdir -p ${stateDir}/{chatgpt,github-copilot,cache}
      if [ ! -e ${stateDir}/proxy.env ]; then
        {
          printf 'LITELLM_MASTER_KEY=sk-%s\n' "$(openssl rand -hex 32)"
          printf 'LITELLM_SALT_KEY=sk-%s\n' "$(openssl rand -hex 32)"
        } > ${stateDir}/proxy.env.tmp
        mv ${stateDir}/proxy.env.tmp ${stateDir}/proxy.env
      fi
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.litellm = {
      inherit image;
      user = "${uid}:${gid}";
      environment = providerEnvironment // {
        # Canonical public issuer for CLI login discovery and OAuth redirects.
        # Do not rely on forwarded headers from the container bridge.
        PROXY_BASE_URL = "https://llm.keidel.me";
        # Prisma's host query parameter selects a Unix socket, not TCP.
        DATABASE_URL = "postgresql://litellm@localhost/litellm?host=/run/postgresql";
      };
      environmentFiles = [ "${stateDir}/proxy.env" ];
      # Only nginx may reach the published port; remote access uses HTTPS.
      ports = [ "127.0.0.1:4000:4000" ];
      volumes = [
        "${proxyConfig}:/etc/litellm/config.yaml:ro"
        "${stateDir}:${stateDir}"
        "/run/postgresql:/run/postgresql:ro"
      ];
      cmd = [
        "--config"
        "/etc/litellm/config.yaml"
        "--host"
        "0.0.0.0"
        "--port"
        "4000"
      ];
      extraOptions = [
        "--userns=host"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
      ];
    };
  };

  systemd.services.podman-litellm = {
    requires = [
      "litellm-init.service"
      "postgresql-setup.service"
    ];
    after = [
      "litellm-init.service"
      "postgresql-setup.service"
    ];
    # A socket-directory bind mount must be recreated after PostgreSQL restarts.
    partOf = [ "postgresql.service" ];
    serviceConfig.UMask = "0077";
  };

  services.nginx.virtualHosts."llm.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    # LiteLLM authenticates UI users and API keys. Browser-only forward auth
    # would break API clients such as Pi.
    locations."/" = {
      proxyPass = "http://127.0.0.1:4000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # LiteLLM inference responses can exceed nginx's default header buffer.
        # Keep buffer sizes consistent even though response-body buffering is off.
        proxy_buffer_size 32k;
        proxy_buffers 8 32k;
        proxy_busy_buffers_size 64k;

        # Stream tokens immediately and allow long-running model requests.
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
      '';
    };
  };

  environment.systemPackages = [ login ];
}
