local player_data = {}

local bots_gui = require("scripts.bots-gui")

function player_data.init(player_index)
  storage.players[player_index] = {
    settings = {},
    bots_window_visible = false, -- Start invisible
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
  player_table.player_index = player.index
  index = game.connected_players[1].index
  assert(player_table.player_index == index, "Player index mismatch: " .. player_table.player_index .. " vs " .. index)
end

function player_data.refresh(player, player_table)
  bots_gui.destroy(player_table)

  paused_is_irrelevant = not player_table.settings.show_delivering and not player_table.settings.show_history
  player_data.update_settings(player, player_table)
  if paused_is_irrelevant and (player_table.settings.show_delivering or player_table.settings.show_history) then
    player_table.paused = false -- unpause if it was paused without any effect
  end

  bots_gui.create_window(player, player_table)
end

return player_data
