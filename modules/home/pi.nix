{
  config,
  host,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  xlsxPackage = pkgs.callPackage ../../packages/pi-xlsx.nix { };
  xlsxExtension = pkgs.runCommand "pi-xlsx-extension" { } ''
    mkdir -p $out
    cp ${./pi-extensions/xlsx.ts} $out/index.ts
    ln -s ${xlsxPackage}/lib/node_modules/pi-xlsx/node_modules $out/node_modules
  '';
in
{
  imports = [
    inputs.pi.homeModules.default
  ];

  programs.pi.coding-agent = {
    enable = true;

    settings.defaultTools = [ "+codemode" ];

    promptTemplates = [
      ./pi-prompts/review.md
    ];

    extensions = [
      ./pi-extensions/commands.ts
      ./pi-extensions/extensions.ts
      ./pi-extensions/permission-gate.ts
      ./pi-extensions/kev.ts
      "${xlsxExtension}/index.ts"
      "${inputs.pi-memory}/index.ts"
      "${inputs.pi-observational-memory}/src/index.ts"
    ]
    ++ lib.optionals (host == "lichtblick") [
      "${inputs.pi-gitlab}/src/index.ts"
      "${inputs.pi-confluence.packages.${pkgs.stdenv.hostPlatform.system}.pi-confluence}/index.ts"
      "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-snowflake}/index.ts"
      ./pi-extensions/jira.ts
    ]
    ++ [
      # Keep the boundary last so it checks commands after RTK rewrites them.
      # ./pi-extensions/stefan-path-protection.ts
    ];
  };

  home.file."code/kev" = {
    source = inputs.kev;
    recursive = true;
  };

  launchd.agents.kev = {
    enable = true;
    domain = "gui";
    config = {
      ProgramArguments = [
        (lib.getExe pkgs.uv)
        "run"
        "--extra"
        "serve"
        "python"
        "-m"
        "kev.serve"
        "--run"
        "jaredpalmer/kev-0.8b"
        "--port"
        "8009"
      ];
      WorkingDirectory = "${config.home.homeDirectory}/code/kev";
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/kev.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/kev.error.log";
    };
  };
}
