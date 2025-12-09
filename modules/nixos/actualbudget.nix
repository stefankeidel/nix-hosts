{
  ...
}: {
  virtualisation.oci-containers = {
    # backend = "docker"; # podman craps out in VM
    containers.actual = {
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

  services.caddy = {
    enable = true;
    virtualHosts."vault.beago-ordinal.ts.net".extraConfig = ''
      reverse_proxy http://127.0.0.1:5006
    '';
  };

  # services.nginx.virtualHosts."vault.beago-ordinal.ts.net" = {
  #   locations = {
  #     "/" = {
  #       proxyPass = "http://127.0.0.1:5006";
  #       proxyWebsockets = true;
  #     };
  #   };
  # };
}
