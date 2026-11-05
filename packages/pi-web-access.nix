{ pkgs, inputs }:

pkgs.buildNpmPackage {
  pname = "pi-web-access";
  version = (builtins.fromJSON (builtins.readFile "${inputs.pi-web-access}/package.json")).version;
  src = inputs.pi-web-access;
  npmDepsHash = "sha256-W8NDa2tq+qGxF4z4lTQXF6mNAOC3bWiuyeeNIIEbStc=";

  # Pi loads TypeScript directly; omit the build toolchain and host-provided peers.
  dontNpmBuild = true;
  npmInstallFlags = [ "--omit=dev" "--legacy-peer-deps" ];
  npmFlags = [ "--ignore-scripts" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp *.ts package.json $out/
    cp -r node_modules $out/
    runHook postInstall
  '';
}
