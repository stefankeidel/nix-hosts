{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "squad-cli";
  version = "0.9.1";

  src = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@bradygaster/squad-cli/-/squad-cli-${version}.tgz";
    hash = "sha512-VL0CU55mhifaImxVUSAel0kfGDWXLfIDJL8ODbTgj3RcG4RuNeFd5iaJQbYK9D5JIdjp3jPU2D+uuCi/pnKEzg==";
  };

  npmDepsHash = "sha256-4druoT9JtLcWkoWY/i1VbCJULt9feuDotZfOA8gQ1A0=";
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
