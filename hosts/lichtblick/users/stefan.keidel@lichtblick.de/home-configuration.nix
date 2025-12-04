{ pkgs, inputs, ... }:
{

  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.home-darwin
  ];

  home = {
    packages = with pkgs; [
      duckdb
      k9s
      kubectl
      kubectx
      kubernetes-helm
      kubelogin
      colima
      (writeShellScriptBin "do_bak" ''
        #!/usr/bin/env zsh
        set -e
        restic --password-file ~/.config/restic-pw --repo rclone:sb:lichtblick-bak backup ~/code ~/Documents ~/Desktop ~/Nextcloud --skip-if-unchanged
        restic --password-file ~/.config/restic-pw --repo rclone:sb:lichtblick-bak forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
      '')
    ];
  };
}
