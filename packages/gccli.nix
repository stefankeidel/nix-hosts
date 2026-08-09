{ pkgs }:
pkgs.buildGoModule rec {
  pname = "gccli";
  version = "1.9.2";

  src = pkgs.fetchFromGitHub {
    owner = "bpauli";
    repo = "gccli";
    rev = "v${version}";
    hash = "sha256-WNL4e8X5efBJeGbDAm5kml/tCi20xT6TSyGs/HOgdIU=";
  };

  subPackages = [ "cmd/gccli" ];
  postPatch = "rm -rf vendor";
  vendorHash = "sha256-CPttt26ScfPfocRSGEkZx3HeoueqCRdADrYSL8RyuLM=";

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${version}"
  ];

  meta = with pkgs.lib; {
    description = "Garmin Connect CLI for health, fitness, and activity data";
    homepage = "https://github.com/bpauli/gccli";
    license = licenses.mit;
    mainProgram = "gccli";
  };
}
