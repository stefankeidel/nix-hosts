{ ... }:

{
  programs.zellij = {
    enable = true;
    enableZshIntegration = false;

    settings = {
      default_mode = "normal";
      options.show_startup_tips = false;
    };
  };
}
