# nix-hosts
Ok, third time's the charm. Start fresh with nix host config

After two mildly successful attempts at nixifying my system config at 

- [v1](https://github.com/stefankeidel/nix-config) which I'd used for ages
- [v2](https://github.com/stefankeidel/nix-cfg) which lifted me to the next level, but
  brought along a lot of cruft I don't understand or need
  
I decided to start fresh using
[numtide/blueprint](https://numtide.github.io/blueprint/main/getting-started/install/)
and a blank slate, copy & pasting only what I really need and understand.

Let's see how it goes.


## Building & Switching Darwin

``` shell
nix run nix-darwin -- build --flake .#lichtblick
HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake ~/code/nix-hosts#lichtblick
```

## Virtual machines

Rig courtesy of [this weekend project](https://github.com/phaer/nixos-vm-on-macos).

``` shell
sudo launchctl start org.nixos.linux-builder
nix run .#nixosConfigurations.minimal-vm.config.system.build.vm -L
```
