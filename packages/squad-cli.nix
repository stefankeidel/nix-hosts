{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "squad-cli";
  version = "0.8.25";

  src = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@bradygaster/squad-cli/-/squad-cli-${version}.tgz";
    hash = "sha512-jnVECwJ+iUZ5swzZqCayCkBpqsScHVZbJPuOw7Tegf11ToHWwcdTseDQDvwlTnquGwKu2GhsoUlba0SitPKKKg==";
  };

  npmDepsHash = "sha256-+htkaZm7M8yD48B+paeVYi7ewDjEjMEoxu7xKybyJbg=";
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
