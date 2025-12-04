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

      /run/current-system/sw/bin/restic --password-file /run/agenix/restic --repo /var/bak/restic backup /var/lib/nextcloud /var/lib/actualbudget --skip-if-unchanged

      /run/current-system/sw/bin/restic --password-file /run/agenix/restic --repo /var/bak/restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 1 --prune

      /run/current-system/sw/bin/rclone -v sync /var/bak/restic/ sb:nixie-bak/

      rm -f /var/lib/nextcloud/db_$d.sql
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
    };
  };
}
