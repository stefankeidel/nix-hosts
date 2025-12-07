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
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak backup --tag mini-2025-12 ~/code ~/Documents ~/Desktop ~/Nextcloud /Volumes/West/Photos\ Library.photoslibrary/ ~/Sync ~/vms --skip-if-unchanged
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak forget --tag mini-2025-12 --keep-daily 7 --keep-weekly 2 --keep-monthly 3 --prune
      '')
    ];
  };
}
