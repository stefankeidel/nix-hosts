{ flake, inputs, hostName }:
import ../../support/mk-darwin-host.nix {
  inherit flake inputs hostName;
  configuration = ./darwin-configuration.nix;
  users.stefan = import ./users/stefan/home-configuration.nix;
}
