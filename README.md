# nix-hosts

Personal Nix configuration for my macOS machines and NixOS server. This repository
manages operating-system settings, user environments, applications, services,
dotfiles, and encrypted secrets from one flake.

It is built around:

- [Nix flakes](https://nixos.wiki/wiki/Flakes) and
  [numtide/blueprint](https://numtide.github.io/blueprint/)
- [nix-darwin](https://github.com/LnL7/nix-darwin) for macOS
- [Home Manager](https://github.com/nix-community/home-manager) for user environments
- [agenix](https://github.com/ryantm/agenix) for encrypted secrets
- [comin](https://github.com/nlewo/comin) for GitOps-style deployment of the NixOS server

This is a personal setup rather than a general-purpose Nix starter. Some modules
contain machine-specific usernames, paths, storage locations, and network settings.

## Hosts

| Host | Platform | Purpose |
| --- | --- | --- |
| `lichtblick` | Apple Silicon macOS | Work MacBook Pro with nix-darwin, Home Manager, development tooling, and work-specific cloud/Kubernetes tools. |
| `mini` | Apple Silicon macOS | Personal Mac mini with nix-darwin, Home Manager, desktop/media applications, and backup tooling. |
| `nixie` | x86_64 NixOS | Server running Nextcloud, Immich, Navidrome, Actual Budget, the `keidel.me` website, centralized authentication, reverse proxying, and backups. |

The macOS hosts follow unstable nixpkgs. `nixie` is intentionally built from the
stable nixpkgs input.

## Repository layout

```text
flake.nix          Flake inputs and top-level Darwin configuration wiring
hosts/             Per-machine system and Home Manager configuration
modules/darwin/    Reusable nix-darwin modules
modules/home/      Shared Home Manager modules, including editor and Pi tooling
modules/nixos/     Reusable NixOS modules
packages/          Locally packaged tools exposed through the flake
dotfiles/           Configuration files linked into Home Manager environments
secrets/           Agenix-encrypted values and their recipient manifest
persistent/        Placeholder for explicitly retained long-lived state
```

Blueprint discovers the reusable modules, packages, and the `nixie` host from the
repository structure. The two Darwin systems are wired explicitly in `flake.nix`
because they use different local usernames and Home Manager configurations.

## Build and switch

Run commands from the repository root.

### macOS

Build a configuration without activating it:

```shell
nix build '.#darwinConfigurations.lichtblick.system'
nix build '.#darwinConfigurations.mini.system'
```

Activate the configuration for the current machine:

```shell
HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake .#lichtblick
# or
HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake .#mini
```

Each Darwin Home Manager configuration also installs a `gonix` helper that runs the
corresponding switch and displays the generation diff with `nvd`.

### NixOS

Build the server configuration:

```shell
nix build '.#nixosConfigurations.nixie.config.system.build.toplevel'
```

`nixie` runs comin and follows the `main` branch of this repository, so merged
changes are deployed through that GitOps flow. From a checkout on the host, a manual
switch can be performed with:

```shell
sudo nixos-rebuild switch --flake .#nixie
```

The pull-request workflow in `.github/workflows/test-linux.yml` builds the same
NixOS output.

## Updating dependencies

Inputs are pinned in `flake.lock`. Update all inputs with:

```shell
nix flake update
```

A scheduled GitHub Actions workflow also opens automated lock-file update pull
requests.

## Secrets

Files under `secrets/*.age` are encrypted; recipient keys are declared in
`secrets/secrets.nix`. Agenix materializes them at activation time with host-specific
owners, paths, and permissions.

Do not commit decrypted values or local credential files. Access to the matching
private age/SSH keys is required to edit or deploy configurations that use these
secrets.
