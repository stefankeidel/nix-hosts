{ pkgs }:

pkgs.buildNpmPackage {
  pname = "pi-snowflake";
  version = "0.1.0";

  src = ../modules/home/pi-extensions/pi-snowflake;
  npmDepsHash = "sha256-zD1fMudl7WN81kJWiq1VXERAY6o2uw0G/htxLNdkZSs=";

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --no-audit --no-fund
    mkdir -p $out
    cp -r index.ts policy.ts package.json node_modules $out/

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Policy-controlled Snowflake query extension for pi";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
