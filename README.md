# nix-hosts
Ok, third time's the charm. Start fresh with nix host config

After two mildly successful attempts at nixifying my system config at 

- [v1](https://github.com/stefankeidel/nix-config) which I'd used for ages
- [v2](github.com/stefankeidel/nix-cfg) which lifted me to the next level, but
  brought along a lot of cruft I don't understand or need
  
I decided to start fresh using
[numtide/blueprint](https://numtide.github.io/blueprint/main/getting-started/install/)
and a blank slate, copy & pasting only what I really need and understand.

Let's see how it goes.

# blueprint docs, from template. TODO: Actually fix

This template shows how you can define and reuse nixos and home-manager modules.


This flake defines two hosts `my-darwin` and `my-nixos`, both importing a
shared `modules/nixos/host-shared.nix` module between them.


Also, both hosts define a `me` user and their home-managed configuration
simply imports `modules/homes/home-shared.nix`.


The idea is you can use this example to get started on how to share
configurations between different system and home environments on different
hosts.
