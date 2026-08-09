{
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    inputs.pi.homeModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    promptTemplates = [
      ./pi-prompts/review.md
    ];

    extensions = [
      ./pi-extensions/commands.ts
      ./pi-extensions/extensions.ts
      "${inputs.pi-gitlab}/src/index.ts"
      "${inputs.pi-confluence.packages.${pkgs.stdenv.hostPlatform.system}.pi-confluence}/index.ts"
      ./pi-extensions/permission-gate.ts
      "${inputs.pi-memory}/index.ts"
      "${inputs.pi-rtk-optimizer}/index.ts"
      # Keep the boundary last so it checks commands after RTK rewrites them.
      ./pi-extensions/stefan-path-protection.ts
    ];
  };
}
