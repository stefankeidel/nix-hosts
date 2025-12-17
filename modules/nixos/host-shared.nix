{pkgs, ...}: {
  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages = [
    pkgs.btop
    pkgs.git
    pkgs.htop
    pkgs.inetutils
    pkgs.nh
    pkgs.ripgrep
  ]; # ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.xbar ]);
}
