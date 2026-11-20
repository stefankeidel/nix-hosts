{ pkgs, inputs }:

pkgs.buildNpmPackage {
  pname = "pi-web-access";
  version = (builtins.fromJSON (builtins.readFile "${inputs.pi-web-access}/package.json")).version;
  src = inputs.pi-web-access;
  npmDepsHash = "sha256-kmyoh7lvHssAhSBU2qKqk9ElGgm6Z5BZUtBjy1+hri4=";

  # Models sometimes fill unused optional strings; keep proxy = "" meaningful.
  postPatch = ''
    substituteInPlace index.ts --replace-fail \
      'async execute(callId, params, signal, onUpdate, ctx) {' \
      'async execute(callId, params, signal, onUpdate, ctx) {
      for (const key of ["model", "provider", "category"]) {
        if (typeof params[key] === "string" && !params[key].trim()) delete params[key];
      }'
  '';

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
