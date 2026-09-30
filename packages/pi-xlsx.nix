{ pkgs }:

pkgs.buildNpmPackage {
  pname = "pi-xlsx";
  version = "1.0.0";
  src = ./pi-xlsx;
  npmDepsHash = "sha256-MzOoawRZ01GVK+m/WCUKiFG1Zfvh4jSoqXb0i7dODJo=";
  dontNpmBuild = true;
  npmInstallFlags = [ "--omit=dev" ];
  npmPruneFlags = [ "--omit=dev" ];
}
