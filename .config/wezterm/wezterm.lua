local wezterm = require "wezterm"

return {
  color_scheme = "Catppuccin Macchiato",

  window_decorations = "RESIZE",
  enable_tab_bar = true,
  tab_bar_at_bottom = false,
  use_fancy_tab_bar = false,
  tab_max_width = 50,
  tab_and_split_indices_are_zero_based = false,

  keys = {
	{
		key = 'r',
		mods = 'CTRL|SHIFT',
		action = wezterm.action.PromptInputLine {
			description = 'Enter tab name:',
			-- initial_value = 'Your tab name...',
			action = wezterm.action_callback(function(window, pane, line)
				-- line will be `nil` if they hit escape without entering anything
				-- An empty string if they just hit enter
				-- Or the actual line of text they wrote
				if line then
					window:active_tab():set_title(line)
				end
			end),
		},
	},
	{
		key = "h",
		mods = "CTRL|SHIFT",
		action = wezterm.action.ActivateTabRelative(-1), -- Move to the left tab
	},
	{
		key = "l",
		mods = "CTRL|SHIFT",
		action = wezterm.action.ActivateTabRelative(1), -- Move to the right tab
	},
	{
		key = "l",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Right"),
	},
	{
		key = "h",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Left"),
	},
	{
		key = "j",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Down"),
	},
	{
		key = "k",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Up"),
	},
	{
		key = "s",
		mods = "CTRL|SHIFT",
		action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "w",
		mods = "SUPER|SHIFT",
		action = wezterm.action.CloseCurrentPane({ confirm = true }),
	},
	{
		key = "w",
		mods = "CTRL|SHIFT",
		action = wezterm.action.CloseCurrentTab({confirm=true}),
	},
	{
		key = 't',
		mods = "CTRL|SHIFT",
		action = wezterm.action.SpawnTab('CurrentPaneDomain'),
	},
}
}
