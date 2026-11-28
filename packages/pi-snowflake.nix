{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-snowflake";
  version = "0.2.0";

  src = pkgs.lib.cleanSourceWith {
    src = ../modules/home/pi-extensions/pi-snowflake;
    filter = path: _type: builtins.baseNameOf path != "node_modules";
  };
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp index.ts query.ts policy.ts package.json README.md $out/

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Policy-controlled Snowflake CLI query tool for pi via fnox MCP";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
