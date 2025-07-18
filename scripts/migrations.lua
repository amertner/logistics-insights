-- Handle changes in configuration and migrations for Logistics Insights mod
local player_data = require("scripts.player-data")
local bots_gui = require("scripts.bots-gui")
local TickCounter = require("scripts.tick-counter")

local function init_storage_and_settings()
  player_data.init_storages()
  for i, player in pairs(game.players) do
    player_data.refresh(player, storage.players[i])
  end
end

local function reinitialise_ui()
  local player = player_data.get_singleplayer_player()
  local player_table = player_data.get_singleplayer_table()
  if player and player_table then
    player_table.ui = nil -- Reset UI to force recreation
    bots_gui.ensure_ui_consistency(player, player_table)
  else
    -- If we can't get the player or table, just re-initialise storage and settings
    init_storage_and_settings()
  end
end

local li_migrations = {
  ["0.8.3"] = function()
    -- Changed the UI layout, so re-initialise it
    reinitialise_ui()
  end,

  ["0.8.5"] = function()
    -- Added tags to certain cells to control tooltips, so re-generate the UI
    reinitialise_ui()
  end,

  ["0.8.9"] = function()
    -- Initialize the new History Timer object
    local player_table = player_data.get_singleplayer_table()
    if player_table then
      player_table.history_timer = TickCounter.new()
      -- The paused state is now contained within the history timer
      if player_table.paused then
        player_table.history_timer:pause()
      end
      player_table.paused = nil -- Remove old paused state
    end
  end,
}

return li_migrations
