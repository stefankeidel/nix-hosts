{ inputs, ... }:

{
  imports = [
    inputs.pi.homeModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    extensions = [
      ./pi-extensions/commands.ts
      ./pi-extensions/gitlab-mr-feedback.ts
      ./pi-extensions/permission-gate.ts
    ];
  };
}
