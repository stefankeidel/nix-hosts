{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-doom-emacs-unstraightened.homeModule
  ];
  
  home = {
    # enableNixpkgsReleaseCheck = false;

    # common darwin pkgs
    # they're all somewhat dev machines, right!?
    # install the heavier stuff we may not need
    # on minimal boxes here
    packages = with pkgs; [
      alejandra
      codex
      codex-acp
      colima
      docker-buildx
      docker-client
      emacs-lsp-booster
      feishin
      kalker
      mise
      nixd
      nodejs
      nvd
      podman
      poppler-utils
      postgresql
      pre-commit
      pwgen
      python313
      tidy-viewer
      tree-sitter
      ty
      uv
      yarn
      yq
    ];

    sessionVariables = {
      EDITOR = "vim";
      VISUAL = "vim";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      MANPAGER = "less -X";
      PYTHONBREAKPOINT = "pudb.set_trace";
      BAT_THEME = "TwoDark";

      LSP_USE_PLISTS = "true";

      # correct grey for zsh autocomplete
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=243";

      # no async fetching of azure sub on every prompt
      SPACESHIP_AZURE_SHOW = "false";
      SPACESHIP_PROMPT_ASYNC = "false"; # irritating af
      SPACESHIP_DOCKER_SHOW = "false"; # what good does the version do

      # Always-true work stuff
      # ok to put this in personal stuff too
      AIRFLOW_UID = 502;
      AIRFLOW_GID = 0;
      AIRFLOW_PLATFORM = "linux/arm64";
    };

    # all my dotfiles, should probably be modularized
    # at some point(tm)
    #
    # emacs config
    # file.".config/doom" = {
    #   source = ../../dotfiles/doom-emacs;
    #   recursive = true;
    # };

    file.".vimrc".source = ../../dotfiles/vim_config;
    file.".wezterm.lua".source = ../../dotfiles/weztermconfig.lua;
    file.".functions".source = ../../dotfiles/functions;
    file.".hushlogin".source = ../../dotfiles/hushlogin;
    # probably replaced by inline config, i.e. properly nixified
    # file.".gitconfig".source = ../../dotfiles/gitconfig;
    file."./.dbt/profiles.yml".source = ../../dotfiles/dbt-profiles.yml;
    file.".config/direnv/direnv.toml".source = ../../dotfiles/direnv.toml;

    file.".vim/backups/.keep".source = builtins.toFile "keep" "";
    file.".vim/swaps/.keep".source = builtins.toFile "keep" "";
    file.".vim/undo/.keep".source = builtins.toFile "keep" "";
    file."/Library/Application Support/Code/User/settings.json".source = ../../dotfiles/vscode-settings.json;
    file."/Library/Application Support/Code - Insiders/User/settings.json".source = ../../dotfiles/vscode-settings.json;
  };

  programs = {
    home-manager.enable = true;
    bat.enable = true;
    tmux.enable = true;
    jq.enable = true;
    direnv.enable = true;

    aerospace = {
      enable = true;
      launchd.enable = true;

      settings = {
        "config-version" = 2;
        "after-startup-command" = [];
        "start-at-login" = true;
        "enable-normalization-flatten-containers" = true;
        "enable-normalization-opposite-orientation-for-nested-containers" = true;
        "accordion-padding" = 30;
        "default-root-container-layout" = "tiles";
        "default-root-container-orientation" = "auto";
        "on-focused-monitor-changed" = ["move-mouse monitor-lazy-center"];
        "automatically-unhide-macos-hidden-apps" = true;
        "persistent-workspaces" = ["1" "2" "3" "f1" "f2" "f3"];
        "on-mode-changed" = [];

        "key-mapping".preset = "qwerty";

        gaps = {
          inner.horizontal = 0;
          inner.vertical = 0;
          outer.left = 0;
          outer.bottom = 0;
          outer.top = 0;
          outer.right = 0;
        };

        mode.main.binding = {
          alt-ctrl-f = "layout floating tiling";
          
          "alt-slash" = "layout tiles horizontal vertical";
          "alt-comma" = "layout accordion horizontal vertical";

          "alt-left" = "focus left";
          "alt-right" = "focus right";
          "alt-up" = "focus up";
          "alt-down" = "focus down";

          "alt-shift-left" = "move left";
          "alt-shift-down" = "move down";
          "alt-shift-up" = "move up";
          "alt-shift-right" = "move right";

          "alt-minus" = "resize smart -50";
          "alt-equal" = "resize smart +50";

          "alt-1" = "workspace 1";
          "alt-2" = "workspace 2";
          "alt-3" = "workspace 3";
          "alt-f1" = "workspace f1";
          "alt-f2" = "workspace f2";
          "alt-f3" = "workspace f3";

          "alt-shift-1" = "move-node-to-workspace 1";
          "alt-shift-2" = "move-node-to-workspace 2";
          "alt-shift-3" = "move-node-to-workspace 3";
          "alt-shift-f1" = "move-node-to-workspace f1";
          "alt-shift-f2" = "move-node-to-workspace f2";
          "alt-shift-f3" = "move-node-to-workspace f3";

          "alt-tab" = "workspace-back-and-forth";

          "alt-enter" = [
            "exec-and-forget open -n -a ~/Applications/Home\\ Manager\\ Apps/Alacritty.app"
          ];
        };

        mode.service.binding = {
          esc = ["reload-config" "mode main"];
          r = ["flatten-workspace-tree" "mode main"];
          f = ["layout floating tiling" "mode main"];
          backspace = ["close-all-windows-but-current" "mode main"];

          "alt-shift-h" = ["join-with left" "mode main"];
          "alt-shift-j" = ["join-with down" "mode main"];
          "alt-shift-k" = ["join-with up" "mode main"];
          "alt-shift-l" = ["join-with right" "mode main"];
        };

        "workspace-to-monitor-force-assignment" = {
          "1" = "main";
          "2" = "main";
          "3" = "main";
          "f1" = "secondary";
          "f2" = "secondary";
          "f3" = "secondary";
        };
      };
    };

    alacritty = {
      enable = true;

      settings = {
        font = {
          normal.family = "Hack Nerd Font";
          size = 19.0;
        };
        window = {
          decorations = "None";
        };
      };

      theme = "doom_one";
    };

    broot = {
      enable = true;

      settings = {
        default_flags = "--no-hidden --no-permissions --no-whale-spotting --sort-by-type-dirs-first";

        verbs = [
          # the default ctrl-l and ctrl-r don't work very well if you
          # actually use MacOS's Mission Control like I do
          {
            invocation = "stefan_panel_left";
            key = "alt-left";
            internal = ":panel_left";
          }
          {
            invocation = "stefan_panel_right";
            key = "alt-right";
            internal = ":panel_right";
          }
        ];
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # bit hacky way to source the theme but it works :shrug:
      initContent = ''
        source ${pkgs.spaceship-prompt}/share/zsh/themes/spaceship.zsh-theme;

        eval "$(/opt/homebrew/bin/brew shellenv)"
        eval "$(mise activate zsh)"

        export XDG_DATA_HOME=$HOME/.local/share
        export XDG_STATE_HOME=$HOME/.local/state
        export XDG_CACHE_HOME=$HOME/.cache

        export PATH=$HOME/.local/bin:$PATH

        source ~/.functions
        source ~/.extra
      '';

      shellAliases = {
        ll = "eza -la";
        l = "eza -l";
        update-nix = "HOME=/var/root sudo darwin-rebuild switch --keep-going -v --flake ~/code/nix-hosts#lichtblick";
        k = "kubectl -n data";
        h = "helm --namespace data";
        dl = "cd ~/Downloads";
      };

      history = {
        size = 1000000;
        save = 1000000;
        append = true;
        extended = true;
        ignoreSpace = true;
        ignoreDups = true;
        ignoreAllDups = true;
        expireDuplicatesFirst = true;
      };

      oh-my-zsh = {
        enable = true;
        plugins = ["git" "z" "terraform" "poetry"];
      };
    };
  };
}
