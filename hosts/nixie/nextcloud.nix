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

  services.nginx.virtualHosts = lib.mkIf config.services.nextcloud.enable {
    ${config.services.nextcloud.hostName} = {
      forceSSL = true;
      enableACME = true;
    };
  };
}
