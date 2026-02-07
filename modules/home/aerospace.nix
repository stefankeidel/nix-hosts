{ config, lib, pkgs, ... }:

{
    programs.aerospace = {
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
        "persistent-workspaces" = ["1" "2" "3" "4" "q" "w" "e"];
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
          "cmd-alt-ctrl-q" = "workspace q";
          "cmd-alt-ctrl-w" = "workspace w";
          "cmd-alt-ctrl-e" = "workspace e";

          "cmd-alt-ctrl-shift-1" = "move-node-to-workspace 1";
          "cmd-alt-ctrl-shift-2" = "move-node-to-workspace 2";
          "cmd-alt-ctrl-shift-3" = "move-node-to-workspace 3";
          "cmd-alt-ctrl-shift-4" = "move-node-to-workspace 4";
          "cmd-alt-ctrl-shift-q" = "move-node-to-workspace q";
          "cmd-alt-ctrl-shift-w" = "move-node-to-workspace w";
          "cmd-alt-ctrl-shift-e" = "move-node-to-workspace e";

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
          "q" = "secondary";
          "w" = "secondary";
          "e" = "secondary";
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
            run = "move-node-to-workspace e";
          }
          {
            "if" = {
              app-id = "org.whispersystems.signal-desktop";
            };
            run = "move-node-to-workspace e";
          }
        ];
      };
    };
}
