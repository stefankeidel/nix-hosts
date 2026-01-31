{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-doom-emacs-unstraightened.homeModule
    inputs.self.homeModules.helix
  ];
  
  home = {
    # enableNixpkgsReleaseCheck = false;

    # common darwin pkgs
    # they're all somewhat dev machines, right!?
    # install the heavier stuff we may not need
    # on minimal boxes here
    packages = with pkgs; [
      alejandra
      bitwarden-cli
      carapace
      codex
      codex-acp
      colima
      docker-buildx
      docker-client
      emacs-lsp-booster
      feishin
      kalker
      lazydocker
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
      starship
      tidy-viewer
      tree-sitter
      ty
      uv
      yarn
      yq
      zoxide
      jankyborders
    ];

    sessionVariables = {
      EDITOR = "hx";
      VISUAL = "hx";
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

      # point Codex at their own home
      CODEX_HOME = "/Users/${config.home.username}/.codex";
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

    sketchybar = {
      enable = true;
      config = {
        source = ../../dotfiles/sketchybar;
        recursive = true;
      };
    };

    nushell = {
      enable = true;
      configFile.source = ../../dotfiles/nushell/config.nu;
      envFile.source = ../../dotfiles/nushell/env.nu;
    };

    aerospace = {
      enable = true;
      launchd.enable = true;

      settings = {
        "config-version" = 2;
        after-startup-command = [
          "exec-and-forget /etc/profiles/per-user/${config.home.username}/bin/borders active_color=0xffe1e3e4 inactive_color=0xff494d64 width=5.0"
        ];
        "start-at-login" = true;
        "enable-normalization-flatten-containers" = true;
        "enable-normalization-opposite-orientation-for-nested-containers" = true;
        "exec-on-workspace-change" = [
          "/bin/bash"
          "-lc"
          "/etc/profiles/per-user/${config.home.username}/bin/sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
        ];
        "accordion-padding" = 30;
        "default-root-container-layout" = "tiles";
        "default-root-container-orientation" = "auto";
        "on-focused-monitor-changed" = ["move-mouse monitor-lazy-center"];
        "automatically-unhide-macos-hidden-apps" = true;
        "persistent-workspaces" = ["1" "2" "3" "4" "f1" "f2" "f3"];
        "on-mode-changed" = [];

        "key-mapping".preset = "qwerty";

        gaps = {
          inner.horizontal = [
            { monitor.main = 3; }
            0
          ];
          inner.vertical = [
            { monitor.main = 3; }
            0
          ];
          outer.left = 0;
          outer.bottom = 0;
          outer.top = 0;
          outer.right = [
            { monitor.main = 40; }
            0
          ];
        };

        mode.main.binding = {
          # All possible modifiers: cmd, alt, ctrl, shift

          # I use Karabiner to map cmd-alt-ctrl to "hyper" as in caps lock
          "cmd-alt-ctrl-slash" = "layout tiles horizontal vertical";
          "cmd-alt-ctrl-comma" = "layout accordion horizontal vertical";

          "cmd-alt-ctrl-left" = "focus left";
          "cmd-alt-ctrl-right" = "focus right";
          "cmd-alt-ctrl-up" = "focus up";
          "cmd-alt-ctrl-down" = "focus down";

          "cmd-alt-ctrl-shift-left" = "move left";
          "cmd-alt-ctrl-shift-down" = "move down";
          "cmd-alt-ctrl-shift-up" = "move up";
          "cmd-alt-ctrl-shift-right" = "move right";

          "cmd-alt-ctrl-minus" = "resize smart -50";
          "cmd-alt-ctrl-equal" = "resize smart +50";

          "cmd-alt-ctrl-1" = "workspace 1";
          "cmd-alt-ctrl-2" = "workspace 2";
          "cmd-alt-ctrl-3" = "workspace 3";
          "cmd-alt-ctrl-4" = "workspace 4";
          "cmd-alt-ctrl-f1" = "workspace f1";
          "cmd-alt-ctrl-f2" = "workspace f2";
          "cmd-alt-ctrl-f3" = "workspace f3";

          "cmd-alt-ctrl-shift-1" = "move-node-to-workspace 1";
          "cmd-alt-ctrl-shift-2" = "move-node-to-workspace 2";
          "cmd-alt-ctrl-shift-3" = "move-node-to-workspace 3";
          "cmd-alt-ctrl-shift-4" = "move-node-to-workspace 4";
          "cmd-alt-ctrl-shift-f1" = "move-node-to-workspace f1";
          "cmd-alt-ctrl-shift-f2" = "move-node-to-workspace f2";
          "cmd-alt-ctrl-shift-f3" = "move-node-to-workspace f3";

          "cmd-alt-ctrl-tab" = "workspace-back-and-forth";

          "cmd-alt-ctrl-semicolon" = "mode service";
          "cmd-alt-ctrl-enter" = "mode apps";
        };

        mode.service.binding = {
          esc = ["reload-config" "mode main"];
          r = ["flatten-workspace-tree" "mode main"];
          f = ["layout floating tiling" "mode main"];
          w = ["close" "mode main"];
          backspace = ["close-all-windows-but-current" "mode main"];
          "left" = ["join-with left" "mode main"];
          "down" = ["join-with down" "mode main"];
          "up" = ["join-with up" "mode main"];
          "right" = ["join-with right" "mode main"];
        };

        mode.apps.binding = {
          # quickest shell  with nu
          enter = ["exec-and-forget open -n -a ~/Applications/Home\\ Manager\\ Apps/Alacritty.app --args -e /etc/profiles/per-user/${config.home.username}/bin/nu" "mode main"];
          # quick firefox with new window
          alt-f = ["exec-and-forget open -n -a /Applications/Firefox.app" "mode main"];
          # fully blown new termin with zsh
          s = ["exec-and-forget open -n -a ~/Applications/Home\\ Manager\\ Apps/Alacritty.app" "mode main"];
          # no new windows for these, when in doubt switch
          f = ["exec-and-forget open -a /Applications/Firefox.app" "mode main"];
          t = ["exec-and-forget open -a /Applications/Microsoft\\ Teams.app" "mode main"];
          o = ["exec-and-forget open -a /Applications/Microsoft\\ Outlook.app" "mode main"];
          e = ["exec-and-forget zsh -lic \"open -a ~/Applications/Home\\ Manager\\ Apps/Emacs.app\"" "mode main"];
          m = ["exec-and-forget open -a ~/Applications/Home\\ Manager\\ Apps/Feishin.app" "mode main"];
        };

        "workspace-to-monitor-force-assignment" = {
          "1" = "main";
          "2" = "main";
          "3" = "main";
          "4" = "main";
          "f1" = "secondary";
          "f2" = "secondary";
          "f3" = "secondary";
        };

        # auto-arrange some stuff across workspaces
        on-window-detected = [
          {
            "if" = {
              app-id = "org.gnu.Emacs";
            };
            run = "move-node-to-workspace 1";
          }
          {
            "if" = {
              app-id = "org.jeffvli.feishin";
            };
            run = "move-node-to-workspace f3";
          }
          {
            "if" = {
              app-id = "org.whispersystems.signal-desktop";
            };
            run = "move-node-to-workspace f3";
          }
        ];
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
        k = "kubectl";
        h = "helm";
        dl = "cd ~/Downloads";
        ff = "aerospace list-windows --all | fzf --bind 'enter:execute(bash -c \"aerospace focus --window-id {1}\")+abort'";
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
