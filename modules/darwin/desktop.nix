#
# Baseline module for common MacOS desktop functionality I use,
# including system-wide packages (rare, basically just emacs and fonts)
#
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    # the default agenix module
    inputs.agenix.nixosModules.default
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # terraform is unfree :-/
  nixpkgs.config.allowUnfree = true;

  # nix linux builder
  nix.linux-builder = {
    enable = true;
    ephemeral = true;
    # config = ({ ... }: {
    #   virtualisation.darwin-builder.diskSize = 30 * 1024;
    # });
  };

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

  environment.systemPackages = with pkgs; [
    (emacs.override {withNativeCompilation = false;})
    #emacs
    inputs.agenix.packages.${stdenv.hostPlatform.system}.default
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.hack
  ];
}
