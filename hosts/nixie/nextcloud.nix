{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.nextcloud = {
    enable = true;

    package = pkgs.nextcloud31;
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

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
  };
}
