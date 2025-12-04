{ config, lib, pkgs, inputs, ... }:

{
  virtualisation.oci-containers.containers = {
    actual = {
      image = "actualbudget/actual-server:25.11.0";

      # bind to tailnet only
      ports = [
        "127.0.0.1:5006:5006"
      ];

      volumes = [
        "/var/lib/actualbudget:/data"
      ];
    };
  };

  services.nginx.virtualHosts."finance.keidel.me" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:5006";
          proxyWebsockets = true;

          # extraConfig = ''
          #   allow 10.0.0.0/8;
          #   allow 127.0.0.1;
          #   deny all;
          # '';
        };
      };
    };
}

