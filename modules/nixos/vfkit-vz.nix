{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types optionalString concatStringsSep mapAttrsToList;

  base = config.virtualisation;
  cfg = config.virtualisation.vfkit-vz;
  hostPkgs = base.host.pkgs;

  kernel = "${config.system.build.toplevel}/kernel";
  initrd = "${config.system.build.toplevel}/initrd";
  cmdline = concatStringsSep " " (
    (config.boot.kernelParams or []) ++ ["init=${config.system.build.toplevel}/init"]
  );
  rosetta = optionalString base.rosetta.enable "--device rosetta,mountTag=${base.rosetta.mountTag}";
  macAddress = optionalString (base.macAddress != null) ",mac=${base.macAddress}";
  sharedDirectories = optionalString (base.sharedDirectories != {}) (
    concatStringsSep " \\\n" (
      mapAttrsToList (
        name: value: "--device virtio-fs,sharedDir=${value.source},mountTag=${name}"
      )
      base.sharedDirectories
    )
  );
  stdioConsole = optionalString cfg.stdioConsole "--device virtio-serial,stdio";
  graphics = optionalString base.graphics ''
    --device virtio-gpu,width=${toString base.resolution.x},height=${toString base.resolution.y} \
    --device virtio-input,pointing \
    --device virtio-input,keyboard \
    --gui \
  '';

  regInfo = hostPkgs.closureInfo {rootPaths = base.additionalPaths;};
  useWritableStoreImage = base.writableStore && !base.writableStoreUseTmpfs;
in {
  options.virtualisation.vfkit-vz = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable building a vfkit runner using bridged networking on macOS (use virtualisation.sharedDirectories for host-mounted persistence).";
    };

    name = mkOption {
      type = types.str;
      default = config.networking.hostName or "nixos-vm";
      description = "Human-friendly VM name used for runner binaries and logging.";
    };

    bridgeInterface = mkOption {
      type = types.str;
      default = "en0";
      description = ''
        Placeholder for future bridging; currently unused. Networking always uses NAT
        with virtio-net in vfkit v0.6.x.
      '';
    };

    stdioConsole = mkOption {
      type = types.bool;
      default = true;
      description = "Attach the virtio console to vfkit stdio (disable when running headless via launchd).";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixpkgs.hostPlatform.system == "aarch64-linux";
        message = "vfkit-vz expects an aarch64-linux guest; adjust the hostPlatform if needed.";
      }
    ];

    system.build.vfkit-vz-runner = let
      storeImage = optionalString base.useNixStoreImage ''
        echo "Creating Nix store image..."

        ${hostPkgs.gnutar}/bin/tar --create \
          --absolute-names \
          --verbatim-files-from \
          --transform 'flags=rSh;s|/nix/store/||' \
          --transform 'flags=rSh;s|~nix~case~hack~[[:digit:]]\+||g' \
          --files-from ${
          hostPkgs.closureInfo {
            rootPaths = [
              config.system.build.toplevel
              regInfo
            ];
          }
        }/store-paths \
          | ${hostPkgs.erofs-utils}/bin/mkfs.erofs \
            --quiet \
            --force-uid=0 \
            --force-gid=0 \
            -L nix-store \
            -U eb176051-bd15-49b7-9e6b-462e0b467019 \
            -T 0 \
            --tar=f \
            "$TMPDIR"/store.img

        echo "Created Nix store image."
      '';

      writableStoreImage = optionalString useWritableStoreImage ''
        if [ ! -f store-writable.img ]
        then
          truncate -s 20G store-writable.img
        fi
      '';

      hostCerts = optionalString base.useHostCerts ''
        mkdir -p "$TMPDIR/certs"
        if [ -e "$NIX_SSL_CERT_FILE" ]; then
          cp -L "$NIX_SSL_CERT_FILE" "$TMPDIR"/certs/ca-certificates.crt
        else
          echo "$NIX_SSL_CERT_FILE should point to a valid file if virtualisation.useHostCerts is enabled."
        fi
      '';
    in
      hostPkgs.writeShellApplication {
        name = "vfkit-${cfg.name}";
        runtimeInputs = [
          hostPkgs.vfkit
          hostPkgs.coreutils
        ];
        text = ''
          #!${hostPkgs.runtimeShell}
          set -euo pipefail

          ${optionalString useWritableStoreImage ''
            ${writableStoreImage}
          ''}

          echo "Starting vfkit VM (${cfg.name}) with bridged networking on ${cfg.bridgeInterface}"

          TMPDIR="$(mktemp --directory --suffix="vfkit-${cfg.name}")"
          trap 'rm -rf "$TMPDIR"' EXIT

          mkdir -p "$TMPDIR/xchg"

          ${storeImage}
          ${hostCerts}

          vfkit \
            --bootloader "linux,kernel=${kernel},initrd=${initrd},cmdline=\"${cmdline}\"" \
            --device "virtio-net,nat${macAddress}" \
            ${stdioConsole} \
            --device virtio-rng \
            ${optionalString base.mountHostNixStore "--device virtio-fs,sharedDir=/nix/store/,mountTag=nix-store"} \
            ${optionalString base.useNixStoreImage "--device nvme,path=\"$TMPDIR\"/store.img"} \
            ${optionalString useWritableStoreImage "--device nvme,path=store-writable.img"} \
            ${sharedDirectories} \
            ${graphics} \
            ${rosetta} \
            --cpus ${toString base.cores} \
            --memory ${toString base.memorySize}
        '';
      };
  };
}
