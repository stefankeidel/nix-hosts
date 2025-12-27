{ ... }:

{
  # mount storage box
  fileSystems."/mnt/storagebox" = {
    device = "u440580@u440580.your-storagebox.de:";
    fsType = "fuse.sshfs";
    options = [
      "Identityfile=/var/lib/id_ed25519"
      "x-systemd.automount" # mount the filesystem automatically on first access
      "allow_other" # don't restrict access to only the user which `mount`s it (because that's probably systemd who mounts it, not you)
      "user" # allow manual `mount`ing, as ordinary user.
      "_netdev"
    ];
  };
  boot.supportedFilesystems."fuse.sshfs" = true;
  programs.fuse.userAllowOther = true;
}
