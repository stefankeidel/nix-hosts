{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.nginx.virtualHosts."keidel.me" = {
    enableACME = true;
    forceSSL = true;
    globalRedirect = "www.keidel.me";
  };

  services.nginx.virtualHosts."www.keidel.me" = {
    forceSSL = true;
    enableACME = true;
    root = inputs.stefan-website;
  };
}
