local player_data = {}

local TickCounter = require("scripts.tick-counter")

-- Cache frequently used functions for performance
local math_max = math.max
local math_ceil = math.ceil

local cached_player = nil
local cached_player_table = nil

---@class PlayerData
---@field settings LuaCustomTable<string,ModSetting>
---@field bots_window_visible boolean
---@field network LuaLogisticNetwork|nil
---@field fixed_network boolean -- Whether to keep watching the current network even if the player moves away
---@field history_timer TickCounter
---@field player_index uint
function player_data.init(player_index)
  storage.players[player_index] = {
    settings = {},
    bots_window_visible = false, -- Start invisible
    network = nil,
    history_timer = TickCounter.new(),
    fixed_network = false,
  }
end

function player_data.init_storages()
  storage.bot_items = {} -- Number of bots delivering and picking right now. Super cheap.
  storage.bot_deliveries = {} -- A list of items being delivered right now
  storage.bot_active_deliveries = {} -- A list of bots currently delivering items
  storage.delivery_history = {} -- A list of past delivered items
  storage.idle_bot_qualities = {} -- Quality of idle bots in roboports
  storage.charging_bot_qualities = {} -- Quality of bots currently charging
  storage.waiting_bot_qualities = {} -- Quality of bots waiting to charge
  storage.roboport_qualities =  {} -- Quality of roboports
  storage.picking_bot_qualities = {} -- Quality of bots currently picking items
  storage.delivering_bot_qualities = {} -- Quality of bots currently delivering items
  storage.other_bot_qualities = {} -- Quality of bots doing anything else
  storage.players = {}
  for i, player in pairs(game.players) do
    player_data.init(i)
    player_data.refresh(player, storage.players[i])
  end
end

function player_data.update_settings(player, player_table)
  local mod_settings = player.mod_settings
  local settings = {
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

function player_data.get_singleplayer_player()
  -- In singleplayer mode, there is only one player. Return the player.
  -- Check if cached player is nil or no longer valid
  if not cached_player or not cached_player.valid then
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
    return true
  end
end

function player_data.toggle_history_collection(player_table)
  player_table.history_timer:toggle()
end

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

function player_data.set_activity_chunks(player_table, chunks)
  -- Scale the update interval based on how often the UI updates, but not too often
  local interval = player_data.ui_update_interval(player_table) / math_max(1, chunks)
  local bot_interval = player_data.bot_chunk_interval(player_table)
  if interval < bot_interval then
    interval = bot_interval
  end

  player_table.current_activity_interval = math_ceil(interval)
end

function player_data.activity_chunk_interval(player_table)
  return player_table.current_activity_interval or 60
end

function player_data.ui_update_interval(player_table)
  return player_table.settings.ui_update_interval or 60
end

function player_data.register_ui(player_table, name)
  if not player_table.ui then
    player_table.ui = {}
  end
  player_table.ui[name] = {}
end

function player_data.refresh(player, player_table)
  if not player_table or not player_table.settings then
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
