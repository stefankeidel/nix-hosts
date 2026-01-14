{
  ...
}: {
  fileSystems."/var/lib/jellyfin/media" = {
    device = "/mnt/share/Media";
    fsType = "none";
    options = [
      "bind"
      "ro"
      "x-systemd.requires-mounts-for=/mnt/share"
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
}
