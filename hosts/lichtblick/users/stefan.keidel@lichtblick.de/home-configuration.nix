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
      feishin
      k9s
      kubectl
      kubectx
      kubelogin
      kubernetes-helm
      (writeShellScriptBin "do_bak" ''
        #!/usr/bin/env zsh
        set -e
        restic --password-file ~/.config/restic-pw --repo rclone:sb:lichtblick-bak backup --tag lichtblick-2025-12 ~/code ~/Documents ~/Desktop ~/Nextcloud ~/Vault --skip-if-unchanged
        restic --password-file ~/.config/restic-pw --repo rclone:sb:lichtblick-bak forget --tag lichtblick-2025-12 --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
      '')
      (writeShellScriptBin "gonix" ''
        #!/usr/bin/env zsh
        set -e
        HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake ~/code/nix-hosts#lichtblick
        current=$(HOME=/var/root sudo nix-env --profile "/nix/var/nix/profiles/system" --list-generations | awk '/current/{print $1}')
        prev=$((current - 1))
        if [[ -e "/nix/var/nix/profiles/system-$current-link" ]]; then
            if [[ -e "/nix/var/nix/profiles/system-$prev-link" ]]; then
                nvd diff /nix/var/nix/profiles/system-{$prev,$current}-link/
            fi
        fi
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
          devices = [ "vault" "mini" ];
        };
      };
  };
}
