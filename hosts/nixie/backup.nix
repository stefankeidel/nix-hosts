{pkgs, ...}: {
  systemd.timers."nextcloud-bak" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "nextcloud-bak.service";
    };
  };

  systemd.services."nextcloud-bak" = {
    script = ''
      set -euo pipefail
      d=`date +"%Y%m%d-%H%M"`

      /run/current-system/sw/bin/nextcloud-occ maintenance:mode --on

      /run/current-system/sw/bin/mysqldump --add-drop-database \
                --complete-insert \
                --create-options \
                nextcloud > /var/lib/nextcloud/db_$d.sql

      /run/current-system/sw/bin/nextcloud-occ maintenance:mode --off

      /run/current-system/sw/bin/pg_dump -U postgres -d accounting -f /var/lib/nextcloud/accounting.sql

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:nixie-bak backup \
        --tag nixie-2026-01 \
        /var/lib/nextcloud

      /run/current-system/sw/bin/restic \
        --password-file /run/agenix/restic \
        --repo rclone:sb:nixie-bak forget \
        --tag nixie-2026-01 \
        --keep-daily 7 --keep-weekly 1 --keep-monthly 1 \
        --prune

      rm -f /var/lib/nextcloud/db_$d.sql
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
    };
  };
}
