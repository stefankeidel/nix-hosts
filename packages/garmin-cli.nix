{ pkgs }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "garmin-cli";
  version = "unstable-2026-07-27";

  src = pkgs.fetchFromGitHub {
    owner = "vicentereig";
    repo = "garmin-cli";
    rev = "ab85ff7a1b8b969a7f287d3c977243e8619264b4";
    hash = "sha256-OZLTJHiuDlfXeNck9GjruXec+LwUeES2mvurSZ71a/M=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = with pkgs.lib; {
    description = "Garmin Connect CLI for fetching activities and health metrics";
    homepage = "https://github.com/vicentereig/garmin-cli";
    license = licenses.mit;
    mainProgram = "garmin-cli";
  };
}
