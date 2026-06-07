{ ... }: {
  systemd.timers."vault-mini-bak" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "vault-mini-bak.service";
    };
  };

  systemd.services."vault-mini-bak" = {
    script = ''
      set -euo pipefail
      d=`date +"%Y%m%d-%H%M"`

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:vault-mini-bak backup \
        --tag vault-mini-2026-01 \
        /var/lib/actualbudget

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:vault-mini-bak forget \
        --tag vault-mini-2026-01 \
        --keep-daily 7 --keep-weekly 1 --keep-monthly 1 \
         --prune
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
