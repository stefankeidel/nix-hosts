#
# Baseline module for common MacOS desktop functionality I use,
# including system-wide packages (rare, basically just emacs and fonts)
#
{
  config,
  pkgs,
  lib,
  inputs,
  hostName,
  ...
}:

# let
#   emacs = pkgs.emacs.override {
#     withNativeCompilation = false;
#     withSQLite3 = true;
#     withTreeSitter = true;
#     withWebP = true;
#   };

#   emacs-with-packages = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs: with epkgs; [
#     vterm
#     treesit-grammars.with-all-grammars
#   ]);
# in
let
  # Let each nixpkgs release elaborate its own platform settings.
  importPkgs = source: import source {
    localSystem.system = config.nixpkgs.hostPlatform.system;
    config = {
      allowUnfree = true;
      # Upstream marks Fabric broken with Invoke >= 3; allow it explicitly.
      problems.handlers.fabric.broken = "warn";
    };
  };
in
{
  imports = [
    # the default agenix module
    inputs.agenix.nixosModules.default
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  nixpkgs = {
    # Keep nix-darwin's evaluator on 26.05 but use 26.11 for host packages.
    source = inputs.nix-26-11;
    flake.source = inputs.nix-26-11.outPath;
    pkgs = importPkgs inputs.nix-26-11;
  };

  home-manager.extraSpecialArgs = {
    host = hostName;
    pkgsUnstable = importPkgs inputs.nixpkgs;
  };

  # The 26.05 HTML manual uses a flag removed by the 26.11 docs renderer.
  documentation.doc.enable = false;

  # Disable auto-start, use 'sudo launchctl start org.nixos.linux-builder'
  launchd.daemons.linux-builder.serviceConfig = {
    KeepAlive = lib.mkForce false;
    RunAtLoad = lib.mkForce false;
  };

  # trackpad stuff
  system.defaults.trackpad.TrackpadRightClick = true;
  system.defaults.trackpad.Clicking = false;
  system.defaults.NSGlobalDomain."com.apple.trackpad.enableSecondaryClick" = true;
  system.defaults.NSGlobalDomain."com.apple.trackpad.trackpadCornerClickBehavior" = 1;
  system.defaults.NSGlobalDomain."com.apple.trackpad.forceClick" = true;

  # mouse accelleration
  system.defaults.".GlobalPreferences"."com.apple.mouse.scaling" = -1.0;

  # key repeat
  system.defaults.NSGlobalDomain.KeyRepeat = 2;

  system.defaults.dock.orientation = "left";

  # various auto subs
  system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticInlinePredictionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled = false;
  system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled = false;

  system.defaults.NSGlobalDomain.AppleFontSmoothing = 2;
  system.defaults.finder.AppleShowAllExtensions = true;
  system.defaults.finder.ShowStatusBar = true;
  system.defaults.finder.ShowPathbar = true;

  system.defaults.finder.QuitMenuItem = true;
  system.defaults.finder._FXShowPosixPathInTitle = true;
  system.defaults.finder._FXSortFoldersFirst = true;
  system.defaults.finder.FXDefaultSearchScope = "SCcf";
  system.defaults.finder.FXEnableExtensionChangeWarning = false;

  system.defaults.finder.FXPreferredViewStyle = "Nlsv";

  system.defaults.dock.minimize-to-application = true;
  system.defaults.dock.show-recents = false;

  # Use Touch ID for sudo
  security.pam.services.sudo_local = {
    enable = true;
    touchIdAuth = true;
    reattach = true;
  };

  # The platform the configuration will be used on.
  # If you're on an Intel system, replace with "x86_64-darwin"
  #nixpkgs.hostPlatform = "aarch64-darwin";

  # Declare the user that will be running `nix-darwin`.
  # users.users."${userConfig.name}" = {
  #   name = "${userConfig.name}";
  #   home = "${userConfig.home}";
  # };

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # The 26.05 uninstaller evaluates its own system and requires a matching nixpkgs.
  system.tools.darwin-uninstaller.enable = false;
  environment.systemPackages = with pkgs; [
    inputs.nix-darwin.packages.${stdenv.hostPlatform.system}.darwin-uninstaller
    #emacs-with-packages
    inputs.agenix.packages.${stdenv.hostPlatform.system}.default
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.hack
    iosevka
  ];
}
