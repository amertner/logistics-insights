local migration = require("__flib__.migration")

local player_data = require("scripts.player-data")
local bot_counter = require("scripts.bot-counter")
local activity_counter = require("scripts.activity-counter")
local controller_gui = require("scripts.controller-gui")
local bots_gui = require("scripts.bots-gui")
local utils = require("scripts.utils")
local migrations = require("scripts.migrations")

---@alias SurfaceName string

---@class ResultLocationData
---@field position MapPosition
---@field surface SurfaceName
---@field items LuaEntity[]

-- STORAGE


local function init_storages()
  storage.bot_items = {}
  storage.bot_deliveries = {}
  storage.bot_active_deliveries = {}
  storage.delivery_history = {}
  storage.players = {}
  for i, player in pairs(game.players) do
    player_data.init(i)
    player_data.refresh(player, storage.players[i])
  end
end

script.on_init(function()
  -- Called when the mod is first added to a save
  init_storages()
  local player = player_data.get_singleplayer_player()
  if player then
    controller_gui.create_window(player)
    bots_gui.create_window(player_data.get_singleplayer_player(), player_data.get_singleplayer_table())
  end
end)

script.on_load(function()
  -- Called when the mod is loaded from a save where it was already added
end)

-- PLAYER

script.on_event({ defines.events.on_player_created }, function(e)
  -- Called when a game is created or a mod is added to an existing game
  local player = game.get_player(e.player_index)
  controller_gui.create_window(player)
  player_data.init(e.player_index)
  player_data.refresh(player, storage.players[e.player_index])
end)

script.on_event(defines.events.on_player_removed, function(e)
  storage.players[e.player_index] = nil
end)

script.on_event(
  { defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed },
  --- @param e EventData.on_player_display_resolution_changed|EventData.on_player_display_scale_changed
  function(e)
    local player = game.get_player(e.player_index)
    if not player then
      return
    end
    if storage.players then
      local player_table = storage.players[e.player_index]
      bots_gui.update(player, player_table)
    end
  end
)

-- SETTINGS

script.on_configuration_changed(function(e)
  if migration.on_config_changed(e, migrations) then
    init_storages()
    for i, player in pairs(game.players) do
      local player_table = storage.players[player.index]
      player_data.refresh(player, storage.players[i])
    end
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if utils.starts_with(e.setting, "li-") then
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()
    bots_gui.destroy(player, player_table)
    player_data.refresh(player, player_table)
    bots_gui.update_chunk_size_cache()
    bots_gui.create_window(player, player_table)
  end
end)

-- TICK

-- Count bots and update the UI
script.on_nth_tick(1, function()
  local player = player_data.get_singleplayer_player()
  local player_table = player_data.get_singleplayer_table()

  if game.tick % 30 == 0 then -- Update this twice a second only
    if player_data.check_network_changed(player, player_table) then
      bot_counter.network_changed(player, player_table)
      activity_counter.network_changed(player, player_table)
    end
  end

  if game.tick % player_data.bot_chunk_interval(player_table) == 0 then
    local bot_progress = bot_counter.gather_bot_data(player, player_table)
    bots_gui.update_bot_chunk_progress(player_table, bot_progress)
  end
  
  if game.tick % player_data.activity_chunk_interval(player_table) == 0 then
    local activity_progress = activity_counter.gather_data(player, player_table)
    bots_gui.update_activity_chunk_progress(player_table, activity_progress)
  end

  if game.tick % player_data.ui_update_interval(player_table) == 0 then
    bots_gui.ensure_ui_consistency(player, player_table)
    controller_gui.update_window(player, player_table)
    bots_gui.update(player, player_table)
  end
end)


-- CONTROLLER

script.on_event(defines.events.on_gui_click, function(event)
  controller_gui.onclick(event)
  bots_gui.onclick(event)
end)

script.on_event(
  { defines.events.on_cutscene_started, defines.events.on_cutscene_finished, defines.events.on_cutscene_cancelled },
  --- @param e EventData.on_cutscene_started|EventData.on_cutscene_finished|EventData.on_cutscene_cancelled
  function(e)
    -- Hide the bots window when a cutscene starts, show it again when it ends
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()

    if player_table and player_table.bots_window_visible then
      player_table.bots_window_visible = player.controller_type ~= defines.controllers.cutscene
    end
  end
)

script.on_event(defines.events.on_player_controller_changed, function(e)
  local player = player_data.get_singleplayer_player()
  local player_table = player_data.get_singleplayer_table()

  bots_gui.update(player, player_table)
end)

script.on_event(
  { defines.events.on_gui_opened, defines.events.on_gui_closed },
  --- @param e EventData.on_gui_opened|EventData.on_gui_closed
  function(e)
    -- Show/hide the GUI when the player opens a locomotive view
    if e.gui_type ~= defines.gui_type.entity or e.entity.type ~= "locomotive" then
      return
    end
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()

    bots_gui.update(player, player_table)
  end
)

script.on_event(defines.events.on_player_changed_surface, function(e)
  local player = game.get_player(e.player_index)
  if not player then return end

  local player_table = storage.players[player.index]
  if not player_table then return end

  window = player.gui.screen.logistics_insights_window
  if window then
    -- If there is a space platform, ricity network, there can't be bots
    window.visible = player_table.bots_window_visible and not player.surface.platform
  end
end)
