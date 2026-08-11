{
  pkgs,
  inputs,
  ...
}:
let
  immichBackup = pkgs.writeShellScriptBin "immich-backup" ''
    set -euo pipefail

    source="sb:immich/"
    destination="/Volumes/SAM/immich/current/"
    lock="''${TMPDIR:-/tmp}/immich-backup.lock"

    if [[ ! -d /Volumes/SAM || ! -w /Volumes/SAM ]]; then
      echo "Immich backup skipped: /Volumes/SAM is not mounted and writable" >&2
      exit 0
    fi

    if ! mkdir "$lock" 2>/dev/null; then
      echo "Immich backup skipped: another backup is already running" >&2
      exit 0
    fi
    trap 'rmdir "$lock"' EXIT

    mkdir -p "$destination"
    echo "Starting Immich backup at $(date -Iseconds)"
    ${pkgs.rclone}/bin/rclone copy "$source" "$destination" \
      --config /Users/stefan/.config/rclone/rclone.conf \
      --create-empty-src-dirs \
      --checkers 8 \
      --transfers 4
    echo "Completed Immich backup at $(date -Iseconds)"
  '';

  immichBackupCheck = pkgs.writeShellScriptBin "immich-backup-check" ''
    set -euo pipefail

    if [[ ! -d /Volumes/SAM || ! -w /Volumes/SAM ]]; then
      echo "Immich backup check skipped: /Volumes/SAM is not mounted and writable" >&2
      exit 0
    fi

    echo "Starting Immich backup check at $(date -Iseconds)"
    ${pkgs.rclone}/bin/rclone check sb:immich/ /Volumes/SAM/immich/current/ \
      --config /Users/stefan/.config/rclone/rclone.conf \
      --one-way
    echo "Completed Immich backup check at $(date -Iseconds)"
  '';
in
{
  imports = [
    inputs.self.homeModules.home-shared
    inputs.self.homeModules.home-darwin
  ];

  home = {
    packages = with pkgs; [
      yt-dlp
      ffmpeg
      immich-go
      immichBackup
      immichBackupCheck
      (writeShellScriptBin "do_bak" ''
        #!/usr/bin/env zsh
        set -e
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak backup --tag mini-2026-07 ~/code ~/Documents ~/Desktop ~/Nextcloud ~/Library/CloudStorage/ProtonDrive-stefan@keidel.me-folder --skip-if-unchanged
        restic --password-file ~/.config/restic-pw --repo rclone:sb:mini-bak forget --tag mini-2026-07 --keep-daily 7 --keep-weekly 2 --keep-monthly 3 --prune
      '')
      (writeShellScriptBin "gonix" ''
        #!/usr/bin/env zsh
        set -e
        HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake ~/code/nix-hosts#mini
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

  # services.syncthing = {
  #     enable = true;

  #     # Optional: GUI credentials (can be set in the browser instead)
  #     settings.gui = {
  #       user = "stefan";
  #       password = "stefan";
  #     };

  #     guiAddress = "127.0.0.1:8384";

  #     settings.devices = {
  #       "lichtblick" = { id = "ZOOJ533-GWZLWPA-EPW5AOT-F327BKZ-6DAQRCC-6D5G7PV-C63SGX4-A53R4AS"; };
  #     };

  #     settings.folders = {
  #       "Vault" = {
  #         path = "/Users/stefan/Vault";
  #         devices = [ "lichtblick" ];
  #       };
  #     };
  # };
}
