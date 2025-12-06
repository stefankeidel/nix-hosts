{
  lib,
  pkgs,
  inputs,
  config,
  ...
}: let
  inherit (lib)
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    unique
    ;

  cfg = config.virtualisation.vfkit-vms;
  defaultUser = config.system.primaryUser or "stefan";
in {
  options.virtualisation.vfkit-vms = {
    enable = mkEnableOption "launchd services for vfkit-vz VM runners";

    instances = mkOption {
      type = types.attrsOf (
        types.submodule ({name, ...}: {
          options = {
            enable = mkEnableOption "manage this VM runner with launchd" // {default = true;};

            host = mkOption {
              type = types.str;
              description = "nixosConfiguration name exposing system.build.vfkit-vz-runner.";
            };

            runAtLoad = mkOption {
              type = types.bool;
              default = false;
              description = "Start the VM when launchd loads the daemon.";
            };

            keepAlive = mkOption {
              type = types.bool;
              default = false;
              description = "Restart the VM if the runner exits.";
            };

            workDir = mkOption {
              type = types.path;
              default = "/Users/${defaultUser}/vms/${name}";
              description = "Working directory for the VM runner (store-writable.img lives here).";
            };

            logPath = mkOption {
              type = types.path;
              default = "/var/log/vfkit-${name}.log";
              description = "Path for stdout/stderr of the VM runner.";
            };
          };
        })
      );
      default = {};
      description = "VMs to expose via vfkit-vz launchd daemons.";
    };
  };

  config = mkIf cfg.enable (
    let
      enabledInstances = filterAttrs (_: inst: inst.enable) cfg.instances;
      runners =
        unique
        (mapAttrsToList
          (_: instCfg: inputs.self.nixosConfigurations.${instCfg.host}.config.system.build.vfkit-vz-runner)
          enabledInstances);

      daemons = mapAttrs' (
        name: instCfg: let
          vmConfig = inputs.self.nixosConfigurations.${instCfg.host};
          runner = vmConfig.config.system.build.vfkit-vz-runner;
          runnerBinary = "vfkit-${vmConfig.config.virtualisation.vfkit-vz.name}";
          daemonName = "vfkit-${name}";
        in
          nameValuePair daemonName {
            path = [pkgs.coreutils];
            serviceConfig = {
              KeepAlive = instCfg.keepAlive;
              RunAtLoad = instCfg.runAtLoad;
              ProcessType = "Background";
              StandardErrorPath = instCfg.logPath;
              StandardOutPath = instCfg.logPath;
            };
            script = ''
              #!${pkgs.runtimeShell}
              set -euo pipefail

              mkdir -p "${instCfg.workDir}"
              cd "${instCfg.workDir}"

              exec ${runner}/bin/${runnerBinary}
            '';
          }
      )
      enabledInstances;
    in {
      environment.systemPackages = runners;
      launchd.daemons = daemons;
    }
  );
}
