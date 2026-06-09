{ pkgs }:

pkgs.stdenvNoCC.mkDerivation rec {
  pname = "gitlab-duo";
  version = "8.101.0";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@gitlab/duo-cli/-/duo-cli-${version}.tgz";
    hash = "sha256-IhX85/Ai54v9yNLM9dwcCGOEMRReyqnWcmyNrDNMMIk=";
  };

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  unpackPhase = ''
    runHook preUnpack

    mkdir source
    tar -xzf "$src" -C source --strip-components=1
    cd source

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/lib/gitlab-duo" "$out/bin"
    cp -R . "$out/lib/gitlab-duo"

    makeWrapper ${pkgs.lib.getExe pkgs.nodejs_22} "$out/bin/duo" \
      --add-flags "$out/lib/gitlab-duo/dist/version-guard.cjs" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ripgrep ]}

    runHook postInstall
  '';

  meta = {
    changelog = "https://gitlab.com/gitlab-org/editor-extensions/gitlab-lsp/-/blob/main/CHANGELOG.md";
    description = "CLI for GitLab AI assistant";
    downloadPage = "https://www.npmjs.com/package/@gitlab/duo-cli";
    homepage = "https://about.gitlab.com/gitlab-duo/";
    license = pkgs.lib.licenses.mit;
    mainProgram = "duo";
  };
}
