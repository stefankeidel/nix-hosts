{
  pkgs,
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
    pkgs.fd
    pkgs.git
    pkgs.httpie
    pkgs.jujutsu
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
      user.email = "1188614+stefankeidel@users.noreply.github.com";

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

    includes = [
      {
        condition = "hasconfig:remote.*.url:*dev.azure.com*";
        contents.user.email = "stefan.keidel@lichtblick.de";
      }
      {
        condition = "hasconfig:remote.*.url:*gitlab.lichtblick.app*";
        contents.user.email = "keidel_dev@lichtblick.de";
      }
    ];
  };

  # programs.doom-emacs = {
  #   enable = true;
  #   doomDir = ../../dotfiles/doom-emacs;

  #   extraPackages = epkgs: with epkgs; [
  #     treesit-grammars.with-all-grammars
  #     vterm
  #   ];
  # };

  home.stateVersion = "24.11"; # initial home-manager state
}
