# AudioMuse-AI on nixie

## Deployment

Create DNS for `audiomuse.keidel.me` pointing to nixie (A, and AAAA only if IPv6
is routed to it). nginx obtains the HTTPS certificate via ACME. Every remote
UI/API route is guarded by Authelia's default two-factor policy; there is no
public API exemption. The app port is published only on `127.0.0.1:8000`.

The stack uses Podman: AudioMuse-AI 3.7.2 Flask and worker containers plus a
private PostgreSQL 15 container with no published database port. Database
credentials are generated on nixie, not stored in Nix. Navidrome 0.64.2 stays
on the flake's pinned unstable package, with the matching unstable NixOS module
and AudioMuse-AI v10 `navidromePlugins.audiomuseai` WASM plugin. The rest of
nixie stays on stable. Unstable bundles plugins in a separate wrapper, allowing
the unmodified Navidrome binary to be substituted from cache.

Include the new module in Git before building/deploying via the Git flake.
Validate and deploy using the usual nixie workflow:

```sh
nix build .#nixosConfigurations.nixie.config.system.build.toplevel
```

This requires a Linux builder. Audio analysis requires substantial CPU, RAM
(upstream recommends at least 8 GB) and temporary disk space. On x86_64 the
standard image requires AVX2; verify nixie's virtual CPU exposes it before
starting analysis. No direct mount of the rclone music library is needed:
AudioMuse-AI downloads audio through Navidrome's API.

## One-Time Setup

1. Open `https://audiomuse.keidel.me` and authenticate with Authelia.
2. In the AudioMuse-AI wizard, add Navidrome with URL
   `http://host.containers.internal:4533` and a Navidrome account (or supported
   API key). This hostname resolves to the Podman host inside both app
   containers. Use a dedicated Navidrome account if desired; playlists belong
   to the configured account.
3. Enable AudioMuse-AI's own authentication and choose a strong API token.
   Authelia protects remote access, but the plugin calls the loopback API
   directly and authenticates with this token. Keep it out of Git.
4. In Navidrome's Settings > Plugins, enable/configure AudioMuse-AI, grant its
   required permissions and user access, and set the API URL to
   `http://127.0.0.1:8000`. Enter the same API token. If requested, set Server
   Name to the name assigned in AudioMuse-AI's multi-server setup.
5. Start an analysis in AudioMuse-AI and let it finish. Test Similar Song there,
   then Instant Mix and artist Radio in Navidrome. The configured agents order
   puts AudioMuse-AI before Last.fm and Deezer.

## Validation

On nixie:

```sh
systemctl status audiomuse-init podman-audiomuse-{postgres,flask,worker} navidrome
journalctl -u podman-audiomuse-flask -u podman-audiomuse-worker -u navidrome
sudo podman exec audiomuse-flask getent hosts host.containers.internal
sudo podman exec audiomuse-flask curl -fsS http://host.containers.internal:4533/ping
curl -I https://audiomuse.keidel.me/
ss -ltn | grep ':8000'
```

An unauthenticated HTTPS request must redirect to Authelia, not serve the wizard
or app. Port 8000 must listen only on loopback and be unreachable remotely.
Verify the plugin's authenticated API requests succeed when triggering Instant
Mix; an empty result before analysis completes is expected.

## State And Updates

All persistent state is under `/var/lib/audiomuse` (root-only parent):
PostgreSQL data, its generated `postgres.env`, and separate Flask/worker plugin,
index-cache and temporary-audio directories. The database contains server
credentials, authentication settings and analysis results. Back it up with
`pg_dump` via `sudo podman exec audiomuse-postgres pg_dump -U audiomuse -d
audiomusedb`, or stop all three containers before copying the data directory;
do not copy a running PostgreSQL data directory as a backup. Also preserve
`postgres.env` and installed plugin directories. Backup scheduling is not added
by this module.

Keep Navidrome, the plugin and core compatible when updating. Bump the shared
image in `audiomuse.nix` for both app containers together, inspect upstream
release notes, and back up first. Do not change PostgreSQL's major image version
without a database migration. Setup wizard and plugin tokens remain runtime
configuration, so no agenix secret changes are required.
