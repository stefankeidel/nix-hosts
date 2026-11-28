{ flake, inputs, hostName }:
import ../../support/mk-darwin-host.nix {
  inherit flake inputs hostName;
  configuration = ./darwin-configuration.nix;
  users."stefan.keidel@lichtblick.de" = import (./users + "/stefan.keidel@lichtblick.de/home-configuration.nix");
}
