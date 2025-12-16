{ ... }: {
  systemd.timers."vault-bak" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "vault-bak.service";
    };
  };

  systemd.services."vault-bak" = {
    script = ''
      set -euo pipefail
      d=`date +"%Y%m%d-%H%M"`

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:vault-bak backup \
        --tag vault-2025-12 \
        /var/lib/syncthing /var/lib/actualbudget /var/lib/paperless

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:vault-bak forget \
        --tag vault-2025-12 \
        --keep-daily 7 --keep-weekly 1 --keep-monthly 1 \
         --prune
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
