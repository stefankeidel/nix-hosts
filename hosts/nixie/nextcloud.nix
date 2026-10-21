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
    # Backport NixOS/nixpkgs@ee62357e90778a37aa7aa4a646e7ccd4fdb643b3
    # (CVE-2026-109618/CVE-2026-109619) without updating the stable package set.
    phpPackage = pkgs.php84.buildEnv {
      version = "8.4.27";
      hash = "sha256-slMKh3xyL0sIyeF0owywi6wrfhkD7m6eMV8KqfX4LCQ=";
      extensions = { enabled, ... }: map (ext:
        if ext.extensionName == "filter" then
          ext.overrideAttrs (old: {
            # The new CGI subprocess tests assume filter is compiled in.
            # Nix builds it shared, so load it in the child processes too.
            postPatch = (old.postPatch or "") + ''
              substituteInPlace \
                ext/filter/tests/oom_filter_default_encoded.phpt \
                ext/filter/tests/oom_filter_input.phpt \
                ext/filter/tests/oom_filter_input_array.phpt \
                --replace-fail "getenv('TEST_PHP_CGI_EXECUTABLE'), '-n'," \
                  "getenv('TEST_PHP_CGI_EXECUTABLE'), '-n', '-d', 'extension=' . __DIR__ . '/../modules/filter.so',"
            '';
          })
        else ext
      ) enabled;
    };
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
