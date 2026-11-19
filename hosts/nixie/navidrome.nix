{ inputs, pkgs, ... }:
{
  disabledModules = [ "services/audio/navidrome.nix" ];
  imports = [
    ({ config, lib, pkgs, ... }:
      let
        navidromeModule = import "${inputs.nixpkgs}/nixos/modules/services/audio/navidrome.nix" {
          inherit config lib pkgs;
        };
      in
      navidromeModule // {
        # Stable's manual redirect table does not know unstable's new sections.
        meta = builtins.removeAttrs navidromeModule.meta [ "doc" ];
      })
  ];

  age.secrets.navidrome-env = {
    file = ../../secrets/navidrome.env.age;
    owner = "navidrome";
    group = "navidrome";
    mode = "600";
    path = "/var/lib/navidrome/navidrome.env";
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    # Keep the package, plugin and module's installation layout aligned.
    package = inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.navidrome;
    withPlugins = plugins: [ plugins.audiomuseai ];

    environmentFile = "/var/lib/navidrome/navidrome.env";

    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/mnt/sb/music";
      LogLevel = "INFO";
      Agents = "audiomuseai,lastfm,deezer";
      Plugins.Enabled = true;
      Scanner.Schedule = "@every 1h";
    };
  };

  systemd.services.navidrome = {
    # Stop/restart Navidrome together with the rclone mount. The assertion
    # prevents a start without the mount, while BindPaths pins the mounted
    # filesystem in Navidrome's namespace instead of ever exposing the bare
    # local directory.
    bindsTo = [ "rclone-mount-sb.service" ];
    partOf = [ "rclone-mount-sb.service" ];
    after = [ "rclone-mount-sb.service" ];
    unitConfig.AssertPathIsMountPoint = "/mnt/sb";
    serviceConfig = {
      BindPaths = [ "/mnt/sb" ];
      # Do not let a stuck scanner retain the FUSE mount indefinitely.
      # systemd escalates to SIGKILL after this timeout and waits for the
      # complete service cgroup to disappear before considering it stopped.
      KillMode = "control-group";
      SendSIGKILL = true;
      TimeoutStopSec = "15s";
    };
  };
}
