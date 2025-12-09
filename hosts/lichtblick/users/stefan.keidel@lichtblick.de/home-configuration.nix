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
        "mini" = { id = "JU7KAPL-2RCNFV4-S4QLXAZ-46R5DZJ-OVO34RS-6MALUQE-5F4L4AA-ZCCZIAJ"; };
      };

      settings.folders = {
        "Vault" = {
          path = "/Users/stefan.keidel@lichtblick.de/Vault";
          devices = [ "vault" ];
        };
      };
  };
}
