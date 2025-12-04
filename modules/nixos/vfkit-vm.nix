{ lib, pkgs, config, ... }:

let
  inherit (lib) mkOption types optionalAttrs;
in
{
  options.virtualisation.vfkit = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable vfkit VM launcher for this NixOS configuration.";
    };

    name = mkOption {
      type = types.str;
      default = "nixos-vm";
      description = "Human-readable VM name used in process/title and logs.";
    };

    memoryMB = mkOption {
      type = types.int;
      default = 4096;
      description = "Memory in MB for the VM.";
    };

    cpus = mkOption {
      type = types.int;
      default = 2;
      description = "Number of vCPUs for the VM.";
    };

    diskImagePath = mkOption {
      type = types.path;
      description = ''Path to qcow2 disk image on the host for the VM root disk.
        The image must exist on the macOS host filesystem.'';
    };

    macAddress = mkOption {
      type = types.str;
      default = "52:54:00:12:34:56";
      description = "MAC address to assign to the VM NIC (use a locally administered MAC).";
    };

    networking = {
      mode = mkOption {
        type = types.enum [ "bridged" "shared" ];
        default = "bridged";
        description = ''Networking mode:
          - bridged: VM joins the physical network and gets its own IP via DHCP
          - shared: VM is NATed behind the host'';
      };

      interface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''When mode=bridged, optionally specify the macOS interface to bridge (e.g., "en0").
          If null, vfkit will choose a default.'';
      };
    };
  };

  config = lib.mkIf config.virtualisation.vfkit.enable {
    # Provide a host-side launcher script to run vfkit with the requested settings.
    system.build.vfkit-runner = pkgs.writeShellApplication {
      name = "vfkit-${config.virtualisation.vfkit.name}";
      runtimeInputs = [ pkgs.vfkit pkgs.coreutils ];
      text = let
        vf = config.virtualisation.vfkit;
        netArg = if vf.networking.mode == "bridged"
                 then "--net vmnet-bridged" + (if vf.networking.interface != null then ",if=${vf.networking.interface}" else "")
                 else "--net vmnet-shared";
      in ''
        set -euo pipefail

        DISK=${lib.escapeShellArg (toString vf.diskImagePath)}
        if [ ! -f "$DISK" ]; then
          echo "Disk image not found: $DISK" >&2
          exit 1
        fi

        echo "Launching vfkit VM: ${vf.name}"
        echo "Memory: ${toString vf.memoryMB} MB, CPUs: ${toString vf.cpus}"
        echo "Disk: $DISK"
        echo "Networking: ${vf.networking.mode} ${vf.networking.interface or ""}"

        # Note: vmnet-bridged requires macOS vmnet entitlement; vfkit is configured for this in nixpkgs.
        # The VM will obtain an IP from the bridged network's DHCP server when in bridged mode.

        exec vfkit \
          --cpus ${toString vf.cpus} \
          --memory ${toString vf.memoryMB} \
          ${netArg} \
          --uuid $(uuidgen) \
          --display none \
          --serial stdio \
          --device virtio-net,mac=${lib.escapeShellArg vf.macAddress} \
          --drive file="$DISK",if=virtio,format=qcow2,readonly=off
      '';
    };

    # Optional: surface a convenience attribute under top-level for discoverability.
    environment.etc."vfkit/${config.virtualisation.vfkit.name}.conf".text = ''
      name=${config.virtualisation.vfkit.name}
      memoryMB=${toString config.virtualisation.vfkit.memoryMB}
      cpus=${toString config.virtualisation.vfkit.cpus}
      diskImagePath=${toString config.virtualisation.vfkit.diskImagePath}
      macAddress=${config.virtualisation.vfkit.macAddress}
      networking.mode=${config.virtualisation.vfkit.networking.mode}
      networking.interface=${toString (config.virtualisation.vfkit.networking.interface or "")}
    '';
  };
}
