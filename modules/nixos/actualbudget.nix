{ inputs, ... }:

{
  virtualisation.oci-containers.containers = {
    actual = {
      image = "actualbudget/actual-server:25.12.0";

      # bind to tailnet only
      ports = [
        "127.0.0.1:5006:5006"
      ];

      volumes = [
        "/var/lib/actualbudget:/data"
      ];
    };
  };

  services.nginx.virtualHosts."budget.keidel.me" = {
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:5006";
          proxyWebsockets = true;
        };
      };
    };
}

