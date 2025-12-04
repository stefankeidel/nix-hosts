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
nix run .#nixosConfigurations.nextcloud.config.system.build.vm -L
```

## vfkit VMs on macOS

- Enable in your NixOS config by importing `modules/nixos/vfkit-vm.nix` and setting:

```
{
  imports = [ ./modules/nixos/vfkit-vm.nix ];

  virtualisation.vfkit = {
    enable = true;
    name = "nixos-vm";
    memoryMB = 4096;
    cpus = 2;
    diskImagePath = /Users/you/vms/nixos-root.qcow2; # existing qcow2
    macAddress = "52:54:00:12:34:56";               # locally administered MAC
    networking.mode = "bridged";                     # own IP via DHCP
    networking.interface = "en0";                    # optional; macOS device to bridge
  };
}
```

- Build your NixOS system to materialize the launcher:

```
nix build .#nixosConfigurations.<your-vm-host>.config.system.build.vfkit-runner
```

- Run vfkit from macOS with the resulting binary:

```
./result/bin/vfkit-nixos-vm
```

- Networking:
  - `bridged`: VM joins the physical network, gets its own IP via DHCP.
  - `shared`: VM is NATed behind the host.

The disk image must be a qcow2 on the macOS host. This module does not create the image; use `qemu-img create -f qcow2 ...` or your preferred tooling.

### Create a qcow2 image

You can use the bundled helper to create a properly formatted qcow2:

``` shell
nix run .#create-qcow2 -- /Users/you/vms/nixos-root.qcow2 40G
```

- Overwrite existing file:

``` shell
nix run .#create-qcow2 -- /Users/you/vms/nixos-root.qcow2 40G --force
```

This uses `qemu-img` to produce a qcow2 suitable for `virtio` in vfkit.