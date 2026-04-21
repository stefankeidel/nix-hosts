{ pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin; # needed on darwin

    enableZshIntegration = true;

    settings = {
      theme = "Catppuccin Frappe";

      "font-family" = "Hack Nerd Font";
      "font-size" = 19.0;
      "scrollback-limit" = 1000000;
      "window-decoration" = "none";
      "undo-timeout" = "0";
      "window-save-state" = "always";

      keybind = [
        # unbind ghostty's default alt+arrow word-jump bindings
        # so they pass through to zellij as focus-change keys
        "alt+left=unbind"
        "alt+right=unbind"
      ];
    };
  };
}
