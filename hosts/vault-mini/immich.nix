{ ... }:

{
  systemd.tmpfiles.rules = [
    "d /mnt/share/Share/Immich 0700 immich immich -"
  ];

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    mediaLocation = "/mnt/share/Share/Immich";

    settings.server.externalDomain = "https://images.keidel.me";
  };

  systemd.services.immich-server.serviceConfig.RequiresMountsFor = [
    "/mnt/share/Share/Immich"
  ];
}
