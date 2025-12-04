-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
   config = wezterm.config_builder()
end

config.color_scheme = 'DoomOne'
config.font = wezterm.font 'Hack Nerd Font'
config.font_size = 19.0

config.window_close_confirmation = 'NeverPrompt'

config.front_end = "WebGpu"

config.keys = {
   -- This will create a new split and run your default program inside it
   {
      key = '/',
      mods = 'ALT',
      action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
   },
   {
      key = 'LeftArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Left',
   },
   {
      key = 'RightArrow',
      mods = 'CMD',
      action = wezterm.action.ActivatePaneDirection 'Right',
   },
}

-- and finally, return the configuration to wezterm
return config
