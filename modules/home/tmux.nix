{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;

    shell = "${pkgs.zsh}/bin/zsh";
    
    terminal = "tmux-256color";
    keyMode = "emacs";
    
    historyLimit = 100000;
    plugins = with pkgs;
      [
        tmuxPlugins.better-mouse-mode
        tmuxPlugins.weather
        tmuxPlugins.tmux-fzf
      ];
    extraConfig = ''
      # Emacs-friendly prefix
      unbind C-b
      set -g prefix C-x
      bind C-x send-prefix

      # Emacs-like window splitting
      bind 2 split-window -v
      bind 3 split-window -h
      bind 0 kill-pane
      bind o select-pane -t :.+
      bind 1 kill-pane -a
    '';
  };
}
