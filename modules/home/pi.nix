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

  # Avoid auto-routing searches through the current model's OpenAI credentials.
  home.file.".pi/agent/web-search.json".text = builtins.toJSON {
    searchProvider = "exa";
  };

  programs.pi.coding-agent = {
    enable = true;

    settings = {
      defaultTools = [ "+codemode" ];
      litellm = {
        providers.litellm = {
          baseUrl = "https://llm.keidel.me";
        };
        # Use this extension for models, not remote tools or prompt injection.
        mcp.enabled = false;
        skills.enabled = false;
      };
    };

    mcp.mcpServers = {
      fnox = {
        command = "fnox";
        args = [ "mcp" ];
      };
    } // lib.optionalAttrs (host == "lichtblick") {
      airflow-dev = {
        url = "https://airflow-mcp.lichtblick-devapps.de/mcp";
        description = "Dev Airflow MCP identity test (whoami only)";
        exposure = "direct";
        oauth.clientRegistration = "dcr";
      };
      airflow-prod = {
        url = "https://airflow-mcp.lichtblick.app/mcp";
        description = "Production Airflow MCP";
        exposure = "direct";
        oauth.clientRegistration = "dcr";
      };
    };

    promptTemplates = [
      ./pi-prompts/review.md
    ];

    extensions = [
      ./pi-extensions/commands.ts
      ./pi-extensions/extensions.ts
      ./pi-extensions/permission-gate.ts
      "${xlsxExtension}/index.ts"
      "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-web-access}/index.ts"
      "${inputs.pi-memory}/index.ts"
      "${inputs.pi-observational-memory}/src/index.ts"
      "${inputs.pi-provider-litellm}/src/index.ts"
      "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-subagents}/index.ts"
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

}
