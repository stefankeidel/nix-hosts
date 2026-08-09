{ inputs, ... }:

{
  imports = [
    inputs.pi.homeModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    extensions = [
      ./pi-extensions/commands.ts
      ./pi-extensions/extensions.ts
      ./pi-extensions/gitlab-mr-feedback.ts
      ./pi-extensions/permission-gate.ts
      "${inputs.pi-memory}/index.ts"
      "${inputs.pi-subagents}/index.ts"
      "${inputs.pi-rtk-optimizer}/index.ts"
      ./pi-extensions/brouter.ts
      # Keep the boundary last so it checks commands after RTK rewrites them.
      ./pi-extensions/stefan-path-protection.ts
    ];
  };
}
