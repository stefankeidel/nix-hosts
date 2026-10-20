# LiteLLM on nixie

## Use it

Connect to Tailscale, then:

- **Web UI:** http://nixie:4000/ui — sign in with your personal admin account.
- **API base:** `http://nixie:4000/v1` — use a virtual key from the UI, not the master key.
- **Models:** `chatgpt/<model-id>` or `github_copilot/<model-id>`, depending on what your subscription supports.

The service is only exposed on localhost and Tailscale. Shared admin/master-key
UI login is disabled; the master key still works for API administration.

## Log in to subscriptions

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
The service uses Podman and native PostgreSQL. Startup may take a moment.
If nixie's Tailscale IP changes, update the explicit port binding in that file.

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
