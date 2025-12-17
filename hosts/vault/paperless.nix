{ ... }:

{
  environment.etc."paperless-admin-pass".text = "admin";

  services.paperless = {
    enable = true;
    passwordFile = "/etc/paperless-admin-pass";

    settings = {
      PAPERLESS_URL = "https://paperless.vault.keidel.me";
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
}
