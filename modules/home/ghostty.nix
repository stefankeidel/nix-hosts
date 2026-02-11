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

        "cmd+w=goto_split:next"
        "cmd+r=reload_config"

        "ctrl+left=goto_split:left"
        "ctrl+down=goto_split:bottom"
        "ctrl+up=goto_split:top"
        "ctrl+right=goto_split:right"

        "ctrl+x>2=new_split:down"
        "ctrl+x>3=new_split:right"
        "ctrl+x>f=toggle_split_zoom"
      ];
    };
  };
}
