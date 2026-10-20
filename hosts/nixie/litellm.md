# LiteLLM on nixie

## Use it

No VPN is required for the UI or API:

- **Web UI:** https://llm.keidel.me/ui — sign in with your personal admin account.
- **API base:** `https://llm.keidel.me/v1` — use a virtual key from the UI, not the master key.
- **Models:** `chatgpt/<model-id>` or `github_copilot/<model-id>`, depending on what your subscription supports.

nginx exposes the service over HTTPS with a Let's Encrypt certificate. Port 4000
is bound only to localhost, with no direct Tailscale or public access.
Shared admin/master-key UI login is disabled; the master key still works for API
administration. Pi uses `https://llm.keidel.me` as its provider base URL.

Unlike apps protected by Authelia, this endpoint relies on LiteLLM's own login
and API-key authentication so API clients can connect without browser redirects.
The login page and any unauthenticated LiteLLM routes are internet-accessible;
this is not a network-level restriction to your laptop. Use a strong, unique
admin password and a dedicated virtual key for Pi with appropriate model/budget
limits. Anyone holding that key can use its permissions; revoke it if leaked.

## Log in to subscriptions

Server administration still requires Tailscale (or another existing private
route to nixie); SSH is not exposed publicly.

```sh
ssh -t stefan@nixie
sudo litellm-login chatgpt
sudo litellm-login github-copilot
```

Run whichever login you need and follow the displayed URL/code. For ChatGPT,
enable device-code authentication in your account's security settings if needed.
Copilot is configured for **lichtblick-se.ghe.com**.

Each login briefly stops LiteLLM and restarts it afterward. Credentials survive
rebuilds and refresh automatically; repeat login if authorization is revoked.
A healthy server doesn't prove provider access works—test a real model request.

## Deploy or troubleshoot

From the repo checkout on nixie:

```sh
sudo nixos-rebuild switch --flake .#nixie
sudo systemctl status podman-litellm
sudo journalctl -u podman-litellm -n 100 --no-pager
curl --fail http://127.0.0.1:4000/health/liveliness
```

Configuration and model aliases live in `hosts/nixie/litellm.nix`, not the UI.
The service uses Podman, native PostgreSQL, and a Nix-managed Valkey cache.
Valkey is local-only over a Unix socket, capped at 256 MiB with LRU eviction
and a 384 MiB systemd memory limit; cache entries expire after 10 minutes and
are not persisted. Startup may take a moment.
DNS for `llm.keidel.me` must point to nixie; ports 80/443 must be reachable for
certificate issuance and HTTPS. After deployment, check the UI and confirm an
unauthenticated request to `/v1/models` is rejected, then test with a virtual key.
Check a streamed model request too; nginx buffering is disabled for token streaming.
The authenticated `/cache/ping` endpoint verifies the cache backend.

For a fresh install, temporarily disable `disable_env_credential_login`, deploy,
and use `admin` plus `LITELLM_MASTER_KEY` from `/var/lib/litellm/proxy.env` to create
a personal proxy-admin account with a password. Re-enable the setting and deploy
again, then test your personal login in a private window.

## Back up before upgrades

The image version is pinned in `litellm.nix`. Upgrades can run database migrations.
There is **no automatic backup job** in this module.

On nixie:

```sh
sudo systemctl stop podman-litellm
sudo -u litellm pg_dump -h /run/postgresql -d litellm -Fc -f /var/lib/litellm/litellm.dump
# Securely copy all of /var/lib/litellm to your backup destination now.
sudo systemctl start podman-litellm
```

That directory contains the database dump, provider tokens, and `proxy.env`
(master/salt keys). Keep it private and out of Git. **Restore the database with
its original keys; changing the salt can make saved credentials unreadable.**
