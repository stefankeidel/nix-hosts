{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # Temporarily disabled while the PHP zero-day is being patched. This only
  # stops the application; Nextcloud data and database configuration are kept.
  services.nextcloud = {
    enable = false;

    package = pkgs.nextcloud34;
    hostName = "cloud.keidel.me";
    https = true;
    database.createLocally = true;

    config = {
      dbtype = "mysql";
      adminpassFile = "/var/lib/nextcloud/nextcloud-admin-pass-file";
    };

    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps) cospend;
    };
  };

  # Keep ownership and the local database intact while the app is disabled.
  users.users.nextcloud = lib.mkIf (!config.services.nextcloud.enable) {
    home = config.services.nextcloud.home;
    group = "nextcloud";
    isSystemUser = true;
  };
  users.groups.nextcloud = {};

  services.mysql = lib.mkIf (!config.services.nextcloud.enable) {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = [ config.services.nextcloud.config.dbname ];
    ensureUsers = [
      {
        name = config.services.nextcloud.config.dbuser;
        ensurePermissions = {
          "${config.services.nextcloud.config.dbname}.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
    extraConfig = lib.mkIf (!config.services.nextcloud.enable) ''
      return 503;
    '';
  };
}
