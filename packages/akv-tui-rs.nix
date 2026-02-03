{ pkgs }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "akv-tui-rs";
  version = "unstable-2026-01-19";

  src = pkgs.fetchFromGitHub {
    owner = "jkoessle";
    repo = "akv-tui-rs";
    rev = "c6bc6dfddee8dd8201f077464457c300837aa843";
    hash = "sha256-eQLKrzip/fQB2DMLtMwz5N5Nmq2tcjGuo2T8D2YhTLM=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = with pkgs.lib; {
    description = "Terminal UI for AKV (Azure Key Vault)";
    homepage = "https://github.com/jkoessle/akv-tui-rs";
    license = licenses.mit;
    mainProgram = "akv-tui-rs";
  };
}
