let
  stefan = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAwU52M/vXuUkthu481OGKYMzFGwc9GfjvVwDLt7yQGeDXUZHx5tpL2NEKSS3imnTfOJp25wFTOAJdF63eznIOUEc+5dCZe8xeZ7IMASGlNQJy51sNUlx986BIjYxLbCl0tykkySs82ZNaog9BapjxiHm2tXb1LFR2CsGOg9mLqRVNxQkOj8KkX5+r/NhVxQRFFW8OJn7rgqsyJtA7vKRwEP+nUsokO3cr/+sWeW7APgrnnkh9iYr/ZG6ibZH/m1+t4yW1kcENVy2X8Gyrs0GWMYQCLrBB+zJYBdwxBdeWSt76QlZnOpdwWcaZEC5PUVzTiKtyUok2NjBoqdpnLezrDw==";
  users = [stefan];

  lichtblick-mac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8aITOuJ7Z9EzI3KV1Opcy5fJldlCQ+5dzHx1QrLj5c";
  nixie = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5v6RSePxjUpyDxV6LpU63AcI7YHSjP5jVM+DMed+/7";
  mini = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEpbyIeJsFejzHM4/r1QDYKjFg52bh/J/HZwE/wWsyCZ";
  vault = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICmSHitiberVrKGoVWpMv4xXEQGq3/ZDKExhqNeEQ+SX";
  systems = [lichtblick-mac nixie mini vault];
in {
  "rclone.conf.age".publicKeys = users ++ systems;
  "restic.age".publicKeys = users ++ systems;
  "pgpass.age".publicKeys = users ++ systems;
  "authinfo.age".publicKeys = users ++ systems;
  "hcloud_token.age".publicKeys = users ++ systems;
  "tailscale-authkey.age".publicKeys = users ++ systems;
  "zsh-extra.age".publicKeys = users ++ systems;
}
