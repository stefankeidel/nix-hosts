{ ... }:
{
  virtualisation.oci-containers.containers.actual = {
    image = "actualbudget/actual-server:26.7.0";

    ports = [
      "127.0.0.1:5006:5006"
    ];

    volumes = [
      "/var/lib/actualbudget:/data"
    ];
  };

  services.nginx.virtualHosts."budget.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:5006";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
