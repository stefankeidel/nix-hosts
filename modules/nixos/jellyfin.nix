{
  ...
}: {
  fileSystems."/var/lib/jellyfin/media" = {
    device = "/mnt/share/Share";
    fsType = "none";
    options = [
      "bind"
      "rw"
      "x-systemd.requires-mounts-for=/mnt/share"
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
}
