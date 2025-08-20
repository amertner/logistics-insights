--- Central definition of player data and related functions for Logistics Insights mod
local player_data = {}

local tick_counter = require("scripts.tick-counter")
local capability_manager = require("scripts.capability-manager")

-- Cache frequently used functions for performance
local math_max = math.max
local math_ceil = math.ceil

-- Global player data, stored for each player
---@class PlayerData
---@field settings table<string,any> -- Player mod settings cached for performance
---@field window LuaGuiElement|nil -- The main window element
---@field bots_window_visible boolean -- Whether the logistics insights window is visible
---@field network LuaLogisticNetwork|nil -- The current logistics network being monitored
---@field fixed_network boolean -- Whether to keep watching the current network even if the player moves away
---@field history_timer TickCounter -- Tracks time for collecting delivery history
---@field player_index uint -- The player's index
---@field window_location {x: number, y: number} -- Saved window position
---@field ui table<string, table> -- UI elements for the mod's GUI
---@field current_logistic_cell_interval number -- Dynamically calculated interval for logistic cell updates
---@field schedule_last_run table<string, uint>|nil -- Per-task last run ticks for scheduler
---@field capabilities table<string, CapabilityRecord>|nil -- Unified capability records
---@param player_index uint
---@return nil
function player_data.init(player_index)
  ---@type PlayerData
  local player_data_entry = {
    settings = {},
    window = nil, -- Will be created later
    bots_window_visible = false, -- Start invisible
    network = nil,
    history_timer = tick_counter.new(),
    fixed_network = false,
    player_index = player_index,
    window_location = {x = 200, y = 0},
    ui = {},
    current_logistic_cell_interval = 60,
    schedule_last_run = {}, -- Per-task last run ticks for scheduler
  }
  storage.players[player_index] = player_data_entry
  capability_manager.init_player(player_data_entry)
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

  storage.bg_refreshing_network_id = nil ---@type number|nil
  --network_data.init() -- Initialise network data storage
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
      show_delivering = mod_settings["li-show-bot-delivering"].value,
      max_items = mod_settings["li-max-items"].value,
      show_history = mod_settings["li-show-history"].value,
      show_activity = mod_settings["li-show-activity"].value,
      ui_update_interval = mod_settings["li-ui-update-interval"].value,
      pause_for_bots = mod_settings["li-pause-for-bots"].value,
      pause_while_hidden = mod_settings["li-pause-while-hidden"].value,
      show_mini_window = mod_settings["li-show-mini-window"].value,
    }
    player_table.settings = settings
    player_table.player_index = player.index
    -- Update capability setting reasons (true = enabled => clear reason; false = disabled => set reason)
    capability_manager.set_reason(player_table, "suggestions", "setting", not settings.show_suggestions)
    capability_manager.set_reason(player_table, "undersupply", "setting", not settings.show_undersupply)
    capability_manager.set_reason(player_table, "history", "setting", not settings.show_history)
    capability_manager.set_reason(player_table, "activity", "setting", not settings.show_activity)
    capability_manager.set_reason(player_table, "delivery", "setting", not settings.show_delivering)
    if player_table.history_timer then
      if capability_manager.is_active(player_table, "history") then
        player_table.history_timer:resume()
      else
        player_table.history_timer:pause()
      end
    end
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

---@return integer The global bot chunk interval setting
function player_data.bot_chunk_interval()
  return tonumber(settings.global["li-chunk-processing-interval-ticks"].value) or 10
end

-- Scale the update interval based on how often the UI updates, but not too often
---@param player_table PlayerData
---@param chunks number
---@return nil
function player_data.set_logistic_cell_chunks(player_table, chunks)
  local interval = player_data.ui_update_interval(player_table) / math_max(1, chunks)
  local bot_interval = player_data.bot_chunk_interval()
  if interval < bot_interval then
    -- The bot interval is the smallest interval we can allow, so don't go lower
    interval = bot_interval
  end

  player_table.current_logistic_cell_interval = math_ceil(interval)
end

---@param player_table PlayerData
---@return integer
function player_data.cells_chunk_interval(player_table)
  return player_table.current_logistic_cell_interval or 60
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


return player_data
