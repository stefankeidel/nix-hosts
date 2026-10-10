# Wanderer (trails.keidel.me)

All persistent data lives under `/var/lib/wanderer`: PocketBase (including
attachments in `pb_data/storage`), Meilisearch, plugins, uploads and the generated
`search.env` / `db.env` secrets. Back up this entire directory; preserve the
existing encryption keys when migrating. Wanderer no longer depends on rclone.

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
