{ lib, ... }:
let
  secretFile = name: ../../secrets + "/${name}.age";
  secretExists = name: builtins.pathExists (secretFile name);
  requiredSecrets = [
    "authelia-jwt-secret"
    "authelia-storage-encryption-key"
    "lldap-admin-password"
    "lldap-jwt-secret"
  ];
  missingSecrets = builtins.filter (name: !(secretExists name)) requiredSecrets;
  haveRequiredSecrets = missingSecrets == [ ];
in
{
  assertions = [
    {
      assertion = haveRequiredSecrets;
      message = ''
        nixie auth services need these agenix secrets:
        ${lib.concatMapStringsSep "\n" (name: "- secrets/${name}.age") missingSecrets}
      '';
    }
  ];

  age.secrets = lib.mkIf haveRequiredSecrets {
    authelia-jwt-secret = {
      file = secretFile "authelia-jwt-secret";
      owner = "authelia-main";
      group = "authelia-main";
      mode = "600";
    };
    authelia-storage-encryption-key = {
      file = secretFile "authelia-storage-encryption-key";
      owner = "authelia-main";
      group = "authelia-main";
      mode = "600";
    };
    lldap-admin-password = {
      file = secretFile "lldap-admin-password";
      owner = "root";
      group = "auth-secrets";
      mode = "640";
    };
    lldap-jwt-secret = {
      file = secretFile "lldap-jwt-secret";
      owner = "lldap";
      group = "lldap";
      mode = "600";
    };
  };

  users.groups.auth-secrets = { };
  users.groups.lldap = { };
  users.users.lldap = {
    isSystemUser = true;
    group = "lldap";
    extraGroups = [ "auth-secrets" ];
  };
  users.users.authelia-main.extraGroups = [ "auth-secrets" ];

  services.lldap = {
    enable = true;
    silenceForceUserPassResetWarning = true;

    settings = {
      ldap_host = "127.0.0.1";
      ldap_port = 3890;
      http_host = "100.96.176.26";
      http_port = 17170;
      http_url = "http://nixie.beago-ordinal.ts.net:17170";
      ldap_base_dn = "dc=keidel,dc=me";
      ldap_user_email = "stefan@keidel.me";
      ldap_user_pass_file = "/run/agenix/lldap-admin-password";
      force_ldap_user_pass_reset = "always";
      jwt_secret_file = "/run/agenix/lldap-jwt-secret";
    };
  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = "/run/agenix/authelia-jwt-secret";
      storageEncryptionKeyFile = "/run/agenix/authelia-storage-encryption-key";
    };

    environmentVariables = {
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = "/run/agenix/lldap-admin-password";
    };

    settings = {
      theme = "auto";
      default_2fa_method = "webauthn";

      server.address = "tcp://127.0.0.1:9091/";

      log = {
        level = "info";
        format = "text";
      };

      access_control.default_policy = "two_factor";

      webauthn = {
        disable = false;
        display_name = "keidel.me";
        selection_criteria = {
          attachment = "";
          discoverability = "preferred";
          user_verification = "preferred";
        };
      };

      totp = {
        disable = false;
        issuer = "keidel.me";
        algorithm = "sha1";
        digits = 6;
        period = 30;
        skew = 1;
        secret_size = 32;
      };

      session = {
        name = "authelia_session";
        same_site = "lax";
        cookies = [
          {
            domain = "keidel.me";
            authelia_url = "https://auth.keidel.me";
            default_redirection_url = "https://www.keidel.me";
          }
        ];
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      authentication_backend.ldap = {
        implementation = "lldap";
        address = "ldap://127.0.0.1:3890";
        base_dn = "dc=keidel,dc=me";
        user = "uid=admin,ou=people,dc=keidel,dc=me";
      };

      notifier.filesystem.filename = "/var/lib/authelia-main/notifications.txt";
    };
  };

  systemd.services.lldap = {
    serviceConfig.DynamicUser = lib.mkForce false;
  };

  systemd.services.authelia-main = {
    requires = [ "lldap.service" ];
    after = [ "lldap.service" ];
  };

  services.nginx.virtualHosts."auth.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:9091";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Uri $request_uri;
      '';
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 17170 ];
}
