{ lib, ... }:
let
  immichOidcClientSecret = ../../secrets/immich-oidc-client-secret.age;
  haveImmichOidcClientSecret = builtins.pathExists immichOidcClientSecret;
in
{
  assertions = [
    {
      assertion = haveImmichOidcClientSecret;
      message = "nixie Immich OIDC needs secrets/immich-oidc-client-secret.age";
    }
  ];

  age.secrets.immich-oidc-client-secret = lib.mkIf haveImmichOidcClientSecret {
    file = immichOidcClientSecret;
    owner = "immich";
    group = "immich";
    mode = "600";
  };

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
      oauth = {
        enabled = true;
        issuerUrl = "https://auth.keidel.me";
        clientId = "immich";
        clientSecret._secret = "/run/agenix/immich-oidc-client-secret";
        scope = "openid email profile";
        signingAlgorithm = "RS256";
        profileSigningAlgorithm = "RS256";
        storageLabelClaim = "preferred_username";
        buttonText = "Sign in with Authelia";
        autoRegister = true;
        autoLaunch = true;
        mobileOverrideEnabled = true;
        mobileRedirectUri = "https://images.keidel.me/api/oauth/mobile-redirect";
        tokenEndpointAuthMethod = "client_secret_post";
      };
      passwordLogin.enabled = false;
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
