{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.home-darwin
  ];

  home = {
    packages = with pkgs; [
      colima
      duckdb
      ffmpeg
      ghostscript
      k9s
      kubectl
      kubectx
      kubernetes-helm
      mosh
      streamlink
      vfkit
      yt-dlp
      (writeShellScriptBin "do_bak" ''
        #!/usr/bin/env zsh
        set -e
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak backup --tag mini-2025-12 ~/code ~/Documents ~/Desktop ~/Nextcloud /Volumes/West/Photos\ Library.photoslibrary/ ~/Vault --skip-if-unchanged
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak forget --tag mini-2025-12 --keep-daily 7 --keep-weekly 2 --keep-monthly 3 --prune
      '')
    ];
  };

  services.syncthing = {
      enable = true;

      # Optional: GUI credentials (can be set in the browser instead)
      settings.gui = {
        user = "stefan";
        password = "stefan";
      };

      guiAddress = "127.0.0.1:8384";

      settings.devices = {
        "vault" = { id = "5BWMPKR-DBAEUCJ-A4F7WCQ-O5GLRTT-YJRCFMC-36E3RPY-JGIHRKV-XHEQBQ3"; };
        "lichtblick" = { id = "ZOOJ533-GWZLWPA-EPW5AOT-F327BKZ-6DAQRCC-6D5G7PV-C63SGX4-A53R4AS"; };
      };

      settings.folders = {
        "Vault" = {
          path = "/Users/stefan/Vault";
          devices = [ "vault" "lichtblick" ];
        };
      };
  };
}
