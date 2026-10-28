{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.nextcloud = {
    enable = true;

    package = pkgs.nextcloud34;
    # nix-stable now includes the PHP 8.4.27 security update
    # (CVE-2026-109618/CVE-2026-109619) and its filter test fix.
    phpPackage = pkgs.php84;
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
