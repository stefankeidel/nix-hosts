{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "squad-cli";
  version = "0.11.0";

  src = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@bradygaster/squad-cli/-/squad-cli-${version}.tgz";
    hash = "sha256-P9CpAbF3gJUOrED3wpc07NrZhjNGYdMjeAruutxZuyw=";
  };

  npmDepsHash = "sha256-rPNLSleMTrvZbhBRs7ue6++fTKu9k8ZHvNVBFgoKsjM=";
  npmInstallFlags = [ "--omit=dev" ];
  npmPruneFlags = [ "--omit=dev" ];
  dontNpmBuild = true;

  postPatch = ''
    cp ${./squad-cli-package-lock.json} package-lock.json
  '';

  meta = with pkgs.lib; {
    description = "Command-line interface for the Squad multi-agent runtime";
    homepage = "https://github.com/bradygaster/squad#readme";
    license = licenses.mit;
    mainProgram = "squad";
    platforms = platforms.all;
  };
}
