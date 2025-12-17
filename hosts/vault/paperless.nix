{ pkgs, ... }:

{
  environment.etc."paperless-admin-pass".text = "admin";

  services.tika = {
    enable = true;
    enableOcr = true;
    port = 9998;
  };

  services.paperless = {
    enable = true;
    passwordFile = "/etc/paperless-admin-pass";

    settings = {
      PAPERLESS_URL = "https://paperless.vault.keidel.me";
      PAPERLESS_TIKA_ENABLED = true;
      PAPERLESS_TIKA_ENDPOINT = "http://127.0.0.1:9998";
      PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://127.0.0.1:3000";
    };
  };

  services.caddy = {
    enable = true;
    # ugly way to unite actual budget which
    # REALLY DOESN'T LIKE TO LIVE OUTSIDE THE ROOT
    # and other services
    virtualHosts."paperless.vault.keidel.me".extraConfig = ''
      reverse_proxy localhost:28981
      tls internal
    '';
  };

  # tried to use the nix service but it kept crapping out :-/
  virtualisation.oci-containers = {
    containers.gotenberg = {
      image = "docker.io/gotenberg/gotenberg:8.25";

      ports = [
        "127.0.0.1:3000:3000"
      ];
    };
  };
}
