# AeroSpace: keyboard-driven tiling on top of macOS, no SIP changes, one config file.
# Remove this file and its import in msaxena.nix to go back to plain macOS windows; the
# JankyBorders focus ring in modules/macos/base.nix can go with it.
{...}: {
  programs.aerospace = {
    enable = true;
    launchd.enable = true; # home-manager owns the agent, so start-at-login stays false
    settings = {
      start-at-login = false;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      accordion-padding = 30;
      gaps = {
        inner = {
          horizontal = 8;
          vertical = 8;
        };
        outer = {
          top = 8;
          bottom = 8;
          left = 8;
          right = 8;
        };
      };

      # alt is the Option key. hjkl because that is what every AeroSpace guide teaches; the
      # Mission Control hotkeys already in use are on ctrl+alt, so nothing collides.
      mode.main.binding = {
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";
        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";
        alt-f = "fullscreen";
        alt-shift-f = "layout floating tiling";
        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-tab = "workspace-back-and-forth";
        alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

        alt-shift-semicolon = "mode service";
      };

      mode.service.binding = {
        esc = ["reload-config" "mode main"];
        r = ["flatten-workspace-tree" "mode main"];
        f = ["layout floating tiling" "mode main"];
        backspace = ["close-all-windows-but-current" "mode main"];
      };

      # Dialog-like apps that should float rather than take a tile.
      on-window-detected = [
        {
          "if".app-id = "com.apple.systempreferences";
          run = ["layout floating"];
        }
        {
          "if".app-id = "com.apple.finder";
          run = ["layout floating"];
        }
        {
          "if".app-id = "com.yubico.yubioath";
          run = ["layout floating"];
        }
      ];
    };
  };
}
