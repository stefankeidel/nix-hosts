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
        "ctrl+n=new_window"

        "ctrl+left=goto_split:left"
        "ctrl+down=goto_split:bottom"
        "ctrl+up=goto_split:top"
        "ctrl+right=goto_split:right"

        "ctrl+a>left=new_split:left"
        "ctrl+a>down=new_split:down"
        "ctrl+a>up=new_split:up"
        "ctrl+a>right=new_split:right"
        "ctrl+a>f=toggle_split_zoom"
      ];
    };
  };
}
