# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` defines inputs and outputs; most work happens via flake commands.  
- Host definitions live in `hosts/<name>`; reusable modules in `modules/{nixos,darwin,home}`; helper packages in `packages/*.nix`.  
- Dotfiles synced through Home Manager are under `dotfiles/`; long-lived state belongs in `persistent/`.  
- Encrypted material is in `secrets/*.age` with the manifest `secrets/secrets.nix` (kept sealed; avoid editing without key access).

## Build, Test, and Development Commands
- Build a macOS host: `nix run nix-darwin -- build --flake .#<darwin-host>`; switch locally with `HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake ~/code/nix-hosts#<darwin-host>`.  
- Build a NixOS VM system: `nix run .#nixosConfigurations.<host>.config.system.build.vm -L`.  
- General validation: `nix flake check` for evaluation sanity before pushing changes.

## Coding Style & Naming Conventions
- Nix files use two-space indentation and trailing commas; prefer attrset ordering that groups related options.  
- Format Nix with `alejandra` (via `nix fmt` when available) to keep diffs minimal.  
- Keep host names and module files lower-case with hyphens or simple words (`vm-base.nix`, `from-qemu-vm.nix`).  
- Keep secrets out of the tree; if adding new ones, wrap with agenix and update `secrets.nix`.

## Testing Guidelines
- For host changes, run the relevant build command above; ensure VM runners still produce binaries.  
- Use `nix flake check` to catch evaluation errors; add small sample builds for new modules when feasible.  
- Name test hosts/modules clearly (e.g., `vm-<feature>.nix`) and delete temporary experiments before committing.

## Commit & Pull Request Guidelines
- Follow the repo’s short, present-tense commit style (`add mini`, `ssh working`); make messages imperative and scoped.  
- PRs should describe the host(s)/modules touched, commands run for validation, and any secrets or manual steps required.  
- Link related issues or deployments; include screenshots or logs when changing VM/darwin workflows.

## Security & Configuration Tips
- Do not commit decrypted secrets or machine-specific tokens; keep `.extra` and similar files local.  
- Verify ownership and permissions for files placed in `persistent/` or VM shared directories; avoid baking credentials into VM images.  
- When bridging networking for vfkit, document MAC addresses and DHCP expectations in host-specific files.
