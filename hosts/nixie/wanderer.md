# Wanderer (trails.keidel.me)

All persistent data lives under `/var/lib/wanderer`: PocketBase (including
attachments in `pb_data/storage`), Meilisearch, plugins, uploads and the generated
`search.env` / `db.env` secrets. Back up this entire directory; preserve the
existing encryption keys when migrating. Wanderer no longer depends on rclone.

## Upgrading to v0.21.0

The database and web containers share `POCKETBASE_PROXY_SECRET` via
`secrets/wanderer-proxy.env.age`, decrypted by agenix to
`/run/agenix/wanderer-proxy-env`. Its plaintext is an environment file containing
`POCKETBASE_PROXY_SECRET=<random value>`. Keep this encrypted file backed up too.
The existing `db.env` and `search.env` keys must not be replaced.

Before deploying, take a consistent backup on nixie (contains secrets; keep private):

```sh
sudo bash -c '
  set -euo pipefail
  install -d -m 0700 /var/backups/wanderer
  systemctl stop podman-wanderer-web.service podman-wanderer-db.service podman-wanderer-search.service
  trap "systemctl start podman-wanderer-web.service" EXIT
  umask 077
  tar -C /var/lib -czf "/var/backups/wanderer/pre-v0.21.0-$(date +%Y%m%d-%H%M%S).tar.gz" wanderer
'
```

After deployment, verify login, existing trails and attachments, and container
logs. Database migrations may run at startup; rolling images back alone is not a
safe rollback. Restore the pre-upgrade data backup with all containers stopped
if rollback is required.

## Before deploying

If there is existing data, stop any running Wanderer containers before copying:

```sh
sudo systemctl stop podman-wanderer-web.service podman-wanderer-db.service podman-wanderer-search.service wanderer-init.service
```

With `/mnt/sb` mounted, copy the former remote attachments and uploads into the
local state directory (check disk space and back up existing local data first):

```sh
mountpoint /mnt/sb
sudo install -d -m 0700 /var/lib/wanderer
sudo mkdir -p /var/lib/wanderer/pb_data/storage /var/lib/wanderer/uploads
sudo rsync -rt /mnt/sb/wanderer/storage/ /var/lib/wanderer/pb_data/storage/
sudo rsync -rt /mnt/sb/wanderer/uploads/ /var/lib/wanderer/uploads/
```

These commands assume the previous split layout in `wanderer.nix`; if the host
still has databases, plugins or environment files elsewhere, migrate those too
before starting the new configuration. Do not regenerate `db.env` for an existing
encrypted database. Do not delete the source data until the migrated instance has
been verified.

Deploy the nixie configuration after migration, then check
`https://trails.keidel.me`, existing trails and attachments, and the
`podman-wanderer-{search,db,web}` service logs.
