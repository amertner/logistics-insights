local player_data = {}

local bots_gui = require("scripts.bots-gui")

function player_data.init(player_index)
  storage.players[player_index] = {
    settings = {},
    bots_window_visible = true,
    network = nil,
    paused = false
  }
end

function player_data.update_settings(player, player_table)
  local mod_settings = player.mod_settings
  local settings = {
    show_delivering = mod_settings["logistics-insights-show-bot-delivering"].value,
    max_items = mod_settings["logistics-insights-max-items"].value,
    show_history = mod_settings["logistics-insights-show-history"].value,
    show_activity = mod_settings["logistics-insights-show-activity"].value,
  }
  player_table.settings = settings
end

function player_data.refresh(player, player_table)
  bots_gui.destroy(player_table)

  player_data.update_settings(player, player_table)

  bots_gui.create_window(player, player_table)
end

return player_data
