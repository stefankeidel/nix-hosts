{ ... }:

{
  systemd.tmpfiles.rules = [
    "d /mnt/share/Share/Immich 0700 immich immich -"
    "d /mnt/share/Share/Immich/backups 0700 immich immich -"
    "d /mnt/share/Share/Immich/encoded-video 0700 immich immich -"
    "d /mnt/share/Share/Immich/library 0700 immich immich -"
    "d /mnt/share/Share/Immich/profile 0700 immich immich -"
    "d /mnt/share/Share/Immich/thumbs 0700 immich immich -"
    "d /mnt/share/Share/Immich/upload 0700 immich immich -"
    "f /mnt/share/Share/Immich/backups/.immich 0600 immich immich -"
    "f /mnt/share/Share/Immich/encoded-video/.immich 0600 immich immich -"
    "f /mnt/share/Share/Immich/library/.immich 0600 immich immich -"
    "f /mnt/share/Share/Immich/profile/.immich 0600 immich immich -"
    "f /mnt/share/Share/Immich/thumbs/.immich 0600 immich immich -"
    "f /mnt/share/Share/Immich/upload/.immich 0600 immich immich -"
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
