--- Central definition of player data and related functions for Logistics Insights mod
local player_data = {}

local global_data = require("scripts.global-data")

-- Cache frequently used functions for performance
local math_max = math.max
local math_ceil = math.ceil

-- Global player data, stored for each player
---@class PlayerData
---@field settings table<string,any> -- Player mod settings cached for performance
---@field window LuaGuiElement|nil -- The main window element
---@field bots_window_visible boolean -- Whether the logistics insights window is visible
---@field networks_window_visible boolean -- Whether the networks window is visible
---@field network LuaLogisticNetwork|nil -- The current logistics network being monitored
---@field fixed_network boolean -- Whether to keep watching the current network even if the player moves away
---@field player_index uint -- The player's index
---@field window_location {x: number, y: number} -- Saved Main window position
---@field networks_window_location {x: number, y: number} -- Saved Networks window position
---@field ui table<string, table> -- UI elements for the mod's GUI
---@field schedule_last_run table<string, uint>|nil -- Per-task last run ticks for scheduler
---@param player_index uint
---@return nil
function player_data.init(player_index)
  ---@type PlayerData
  local player_data_entry = {
    settings = {},
    window = nil, -- Will be created later
    bots_window_visible = false, -- Start invisible
    networks_window_visible = false, -- Start invisible
    network = nil,
    fixed_network = false,
    player_index = player_index,
    window_location = {x = 300, y = 444},
    networks_window_location = {x = 300, y = 100},
    ui = {},
    schedule_last_run = {}, -- Per-task last run ticks for scheduler
  }
  storage.players[player_index] = player_data_entry
end

--- Initialise all storages
---@return nil
function player_data.init_storages()
  ---@type table<uint, PlayerData>
  storage.players = {}
  for _, player in pairs(game.players) do
    player_data.init(player.index)
    player_data.update_settings(player, storage.players[player.index])
  end
end

---@param player LuaPlayer|nil
---@param player_table PlayerData|nil
---@return nil
function player_data.update_settings(player, player_table)
  if  player and player.valid and player_table then
    local mod_settings = player.mod_settings
    local settings = {
      show_undersupply = mod_settings["li-show-undersupply"].value,
      show_suggestions = mod_settings["li-show-suggestions"].value,
      max_items = mod_settings["li-max-items"].value,
      show_history = mod_settings["li-show-history"].value,
      ui_update_interval = mod_settings["li-ui-update-interval"].value,
    }
    player_table.settings = settings
    player_table.player_index = player.index
  end
end

---@param player_index uint
---@return PlayerData|nil
function player_data.get_player_table(player_index)
  if not player_index or not storage.players then
    return nil -- No player index or storage available
  end
  return storage.players[player_index] or nil -- Return the player table if it exists
end

---@param player_table PlayerData
---@return integer
function player_data.ui_update_interval(player_table)
  return player_table.settings.ui_update_interval or 60
end

---@param player_table PlayerData
---@param name string
---@return nil
function player_data.register_ui(player_table, name)
  if not player_table.ui then
    player_table.ui = {}
  end
  player_table.ui[name] = {}
end

-- Check if any players in the set have their main window open
---@param players table<uint, boolean>
---@return boolean True if any players in the set have their main window open
function player_data.players_show_main_window(players)
  if not players then
    return false
  end
  for player_index, _ in pairs(players) do
    local pt = player_data.get_player_table(player_index)
    if pt and pt.bots_window_visible then
      return true
    end
  end
  return false
end

return player_data
