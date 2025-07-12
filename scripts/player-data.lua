local player_data = {}

-- Cache frequently used functions for performance
local math_max = math.max
local math_ceil = math.ceil

local cached_player = nil
local cached_player_table = nil

---@class PlayerData 
---@field settings LuaCustomTable<string,ModSetting>
---@field bots_window_visible boolean
---@field network LuaLogisticNetwork|nil
---@field paused boolean
---@field player_index uint
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
    show_delivering = mod_settings["li-show-bot-delivering"].value,
    max_items = mod_settings["li-max-items"].value,
    show_history = mod_settings["li-show-history"].value,
    show_activity = mod_settings["li-show-activity"].value,
    chunk_size = mod_settings["li-chunk-size"].value,
    bot_chunk_interval = mod_settings["li-chunk-processing-interval"].value,
    ui_update_interval = mod_settings["li-ui-update-interval"].value,
    pause_for_bots = mod_settings["li-pause-for-bots"].value,
    pause_while_hidden = mod_settings["li-pause-while-hidden"].value,
  }
  player_table.settings = settings
  player_table.player_index = player.index
  player_table.current_activity_size = 0
  index = game.connected_players[1].index
  ui = {}
  assert(player_table.player_index == index, "Player index mismatch: " .. player_table.player_index .. " vs " .. index)
end

function player_data.get_singleplayer_table()
  -- In singleplayer mode, there is only one player. Return the player_table.
  if not cached_player_table then
    local player = game.connected_players[1]
    cached_player_table = storage.players[player.index]
  end
  return cached_player_table
end

function player_data.get_singleplayer_player()
  -- In singleplayer mode, there is only one player. Return the player.
  if not cached_player then
    cached_player = game.connected_players[1]
  end
  return cached_player
end

function player_data.toggle_history_collection(player_table)
  player_table.paused = not player_table.paused
end

function player_data.is_paused(player_table)
  return player_table.paused or
          (player_table.settings.pause_while_hidden and not player_table.bots_window_visible)
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
  paused_is_irrelevant = not player_table.settings.show_delivering and not player_table.settings.show_history
  player_data.update_settings(player, player_table)
  if paused_is_irrelevant and (player_table.settings.show_delivering or player_table.settings.show_history) then
    player_table.paused = false -- unpause if it was paused without any effect
  end
end

return player_data
