{
  pkgs,
  osConfig,
  ...
}: {
  # only available on linux, disabled on macos
  # (this is from the examples)
  #
  # services.ssh-agent.enable = pkgs.stdenv.isLinux;

  home.packages = [
    pkgs.coreutils
    pkgs.curl
    pkgs.dua
    pkgs.eza
    pkgs.git
    pkgs.httpie
    pkgs.netcat-gnu
    pkgs.nix-direnv
    pkgs.nmap
    pkgs.pv
    pkgs.rclone
    pkgs.restic
    pkgs.ripgrep
    pkgs.rsync
    pkgs.spaceship-prompt
    pkgs.speedtest-go
    pkgs.unixtools.watch
    pkgs.vim
    pkgs.wget
  ];
  # ++ (
  #   # you can access the host configuration using osConfig.
  #   pkgs.lib.optionals (osConfig.programs.vim.enable && pkgs.stdenv.isDarwin) [ pkgs.skhd ]
  # );

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.diff-so-fancy.enable = true;
  programs.diff-so-fancy.enableGitIntegration = true;

  programs.git = {
    enable = true;

    settings = {
      user.name = "Stefan Keidel";
      user.email = "stefan.keidel@lichtblick.de";

      init = {
        defaultBranch = "main";
      };
      merge = {
        ff = false;
      };
      pull = {
        rebase = true;
      };
    };
    signing = {
      signByDefault = false;
      format = "openpgp";
    };
  };

  home.stateVersion = "24.11"; # initial home-manager state
}
