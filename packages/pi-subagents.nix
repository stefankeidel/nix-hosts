{ pkgs, inputs }:

let
  package = builtins.fromJSON (builtins.readFile "${inputs.pi-subagents}/package.json");
in
pkgs.buildNpmPackage {
  pname = package.name;
  version = package.version;
  src = inputs.pi-subagents;
  npmDepsHash = "sha256-Fx47aupm5P6xV3Fq8kQxs0u7gYNADTnbIZcmpQRdG28=";

  dontNpmBuild = true;
  npmInstallFlags = [ "--omit=dev" "--legacy-peer-deps" ];
  npmFlags = [ "--ignore-scripts" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp index.ts package.json README.md CHANGELOG.md *.mjs *.cjs $out/
    cp -r src agents skills prompts docs $out/
    cp -r node_modules $out/

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = package.description;
    homepage = package.homepage;
    license = licenses.mit;
    platforms = platforms.all;
  };
}
