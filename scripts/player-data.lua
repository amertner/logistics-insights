--- Central definition of player data and related functions for Logistics Insights mod
local player_data = {}

local tick_counter = require("scripts.tick-counter")
local suggestions = require("scripts.suggestions")

-- Record used to show items being delivered right now
---@class DeliveryItem
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many are being delivered

-- Record used to show historically delivered items
---@class DeliveredItems
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many of this item have been delivered
---@field ticks number -- Total ticks for all deliveries of this item
---@field avg number -- Average ticks per delivery, equal to ticks/count

-- Record used to record items being delivered, before they are added to history
---@class BotDeliveringInFlight
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many of this item it is delivering
---@field targetpos MapPosition -- The target position for the delivery
---@field first_seen number -- The first tick this bot was seen delivering it
---@field last_seen number -- The last tick this bot was seen delivering it

-- Cache frequently used functions for performance
local math_max = math.max
local math_ceil = math.ceil

local cached_player = nil
local cached_player_table = nil

-- Global player data, stored for each player
---@class PlayerData
---@field settings table<string,any> -- Player mod settings cached for performance
---@field bots_window_visible boolean -- Whether the logistics insights window is visible
---@field network LuaLogisticNetwork|nil -- The current logistics network being monitored
---@field fixed_network boolean -- Whether to keep watching the current network even if the player moves away
---@field suggestions Suggestions -- Suggestions for improving logistics network
---@field history_timer TickCounter -- Tracks time for collecting delivery history
---@field player_index uint -- The player's index
---@field window_location {x: number, y: number} -- Saved window position
---@field saved_paused_state boolean -- Remembered pause state when window is hidden
---@field ui table<string, table> -- UI elements for the mod's GUI
---@field bots_table LuaGuiElement|nil -- Reference to the main bots table UI element
---@field current_logistic_cell_interval number -- Dynamically calculated interval for logistic cell updates
---@param player_index uint
function player_data.init(player_index)
  ---@type PlayerData
  local player_data_entry = {
    settings = {},
    bots_window_visible = false, -- Start invisible
    network = nil,
    history_timer = tick_counter.new(),
    suggestions = suggestions.new(),
    fixed_network = false,
    player_index = player_index,
    window_location = {x = 200, y = 0},
    saved_paused_state = false,
    ui = {},
    bots_table = nil,
    current_logistic_cell_interval = 60
  }
  storage.players[player_index] = player_data_entry
end

-- Initialize all of the storage elements managed by logistic_cell_counter
---@return nil
function player_data.init_logistic_cell_counter_storage()
  -- Bot qualities
  ---@type QualityTable
  storage.idle_bot_qualities = {} -- Quality of idle bots in roboports

  ---@type QualityTable
  storage.charging_bot_qualities = {} -- Quality of bots currently charging

  ---@type QualityTable
  storage.waiting_bot_qualities = {} -- Quality of bots waiting to charge

  -- Roboport qualities
  ---@type QualityTable
  storage.roboport_qualities = {} -- Quality of roboports
end

-- Initialize all of the storage elements managed by bot_counter
---@return nil
function player_data.init_bot_counter_storage()
  -- Real time data about deliveries
  ---@type table<string, DeliveryItem>
  storage.bot_deliveries = {} -- A list of items being delivered right now

  -- Real time data about bots: Very cheap to keep track of
  ---@type table<string, number>
  storage.bot_items = storage.bot_items or {}

  -- History data
  ---@type table<number, BotDeliveringInFlight>
  storage.bot_active_deliveries = {} -- A list of bots currently delivering items

  ---@type table<string, DeliveredItems>
  storage.delivery_history = {} -- A list of past delivered items

  -- Bot counting: bots seen in the last full pass
  ---@type table<number, boolean>
  storage.last_pass_bots_seen = {}

  -- Bot qualitity tables
  ---@type QualityTable
  storage.picking_bot_qualities = {} -- Quality of bots currently picking items

  ---@type QualityTable
  storage.delivering_bot_qualities = {} -- Quality of bots currently delivering items

  ---@type QualityTable
  storage.other_bot_qualities = {} -- Quality of bots doing anything else

  ---@type QualityTable
  storage.total_bot_qualities = {} -- Quality of all bots counted

  --@type table. TODO: Proper type
  storage.undersupply = {}
end

---@return nil
function player_data.init_storages()
  player_data.init_logistic_cell_counter_storage()
  player_data.init_bot_counter_storage()
  storage.players = {}
  for _, player in pairs(game.players) do
    player_data.init(player.index)
    player_data.refresh(player, storage.players[player.index])
  end
end

---@param player LuaPlayer|nil
---@param player_table PlayerData|nil
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
      gather_quality_data = mod_settings["li-gather-quality-data"].value,
      chunk_size = mod_settings["li-chunk-size"].value,
      bot_chunk_interval = mod_settings["li-chunk-processing-interval"].value,
      ui_update_interval = mod_settings["li-ui-update-interval"].value,
      pause_for_bots = mod_settings["li-pause-for-bots"].value,
      pause_while_hidden = mod_settings["li-pause-while-hidden"].value,
      show_mini_window = mod_settings["li-show-mini-window"].value,
    }
    player_table.settings = settings
    player_table.player_index = player.index
  end
end

---@return PlayerData|nil
function player_data.get_singleplayer_table()
  -- In singleplayer mode, there is only one player. Return the player_table.
  if not cached_player_table then
    -- Make sure there are connected players before trying to access them
    if #game.connected_players > 0 then
      local player = game.connected_players[1]
      if player and player.valid and storage and storage.players then
        cached_player_table = storage.players[player.index]
      else
        -- Player or storage not valid, return nil
        return nil
      end
    else
      -- No players connected, return nil
      return nil
    end
  end
  return cached_player_table
end

---@return LuaPlayer|nil
function player_data.get_singleplayer_player()
  -- In singleplayer mode, there is only one player. Return the player.
  -- Check if cached player is nil or no longer valid
  if not cached_player or not cached_player.valid then
    cached_player = nil -- Clear invalid cache
    -- Make sure there are connected players before trying to access them
    if #game.connected_players > 0 then
      cached_player = game.connected_players[1]
    else
      -- No players connected, return nil
      return nil
    end
  end
  return cached_player
end

---@param player LuaPlayer|nil
---@param player_table PlayerData|nil
---@return boolean # True if the network has changed
function player_data.check_network_changed(player, player_table)
  if not player or not player.valid then
    return false
  end

  if player_table and player_table.fixed_network then
    -- Check that the fixed network is still valid
    if player_table.network and player_table.network.valid then
      return false
    else
      -- The fixed network is no longer valid, so make sure to clear it
      player_table.network = nil
      player_table.fixed_network = false
    end
  end

  -- Get or update the network, return true if the network is changed
  if player_table then
    local network = player.force.find_logistic_network_by_position(player.position, player.surface)
    local player_table_network = player_table.network
    -- Get the network IDs, making sure the network references are still valid
    local new_network_id = network and network.valid and network.network_id
    local old_network_id = player_table_network and player_table_network.valid and player_table_network.network_id

    if new_network_id == old_network_id then
      return false
    else
      player_table.network = network
      player_table.history_timer:reset() -- Reset the tick counter when network changes
      if not player_table.suggestions then
        player_table.suggestions = suggestions.new()
      end
      player_table.suggestions:reset() -- Reset suggestions list
      return true
    end
  else
    return false
  end
end

---@param player_table PlayerData|nil
function player_data.toggle_history_collection(player_table)
  if player_table then
    player_table.history_timer:toggle()
  end
end

---@param player_table PlayerData
---@return boolean
function player_data.is_paused(player_table)
  if player_table.history_timer then
    return player_table.history_timer:is_paused() or
        (player_table.settings.pause_while_hidden and not player_table.bots_window_visible)
  else
    -- History timer may not be initialized yet, so ignore it.
    return (player_table.settings.pause_while_hidden and not player_table.bots_window_visible)
  end
end

function player_data.is_included_robot(bot)
  return true -- For now, include all bots.
  -- return bot and bot.name == "logistics-robot" -- Option to expand in the future
end

function player_data.bot_chunk_interval(player_table)
  return player_table.settings.bot_chunk_interval or 10
end

-- Scale the update interval based on how often the UI updates, but not too often
function player_data.set_logistic_cell_chunks(player_table, chunks)
  local interval = player_data.ui_update_interval(player_table) / math_max(1, chunks)
  local bot_interval = player_data.bot_chunk_interval(player_table)
  if interval < bot_interval then
    interval = bot_interval
  end

  player_table.current_logistic_cell_interval = math_ceil(interval)
end

function player_data.cells_chunk_interval(player_table)
  return player_table.current_logistic_cell_interval or 60
end

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

---@param player LuaPlayer|nil
---@param player_table PlayerData|nil
---@return nil
function player_data.refresh(player, player_table)
  if not player or not player.valid or not player_table or not player_table.settings then
    return
  end

  local paused_is_irrelevant = not player_table.settings.show_delivering and not player_table.settings.show_history
  player_data.update_settings(player, player_table)
  if paused_is_irrelevant and (player_table.settings.show_delivering or player_table.settings.show_history) then
    -- unpause if it was paused without any effect
    player_table.history_timer:resume()
  end

  -- Initialize shortcut toggle state based on window visibility
  player.set_shortcut_toggled("logistics-insights-toggle", player_table.bots_window_visible)
end

-- Reset cached references - should be called when game is loaded or configuration changes
function player_data.reset_cache()
  cached_player = nil
  cached_player_table = nil
end

return player_data
