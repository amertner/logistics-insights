local player_data = require("scripts.player-data")
local bot_counter = require("scripts.bot-counter")
local controller_gui = require("scripts.controller-gui")
local bots_gui = require("scripts.bots-gui")

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
end)

script.on_load(function()
  -- Called when the mod is loaded from a save where it was already added
end)

-- PLAYER

script.on_event({defines.events.on_player_created, defines.events.on_player_joined_game},function(e)
  local player = game.get_player(e.player_index)
  controller_gui.create_window()
  player_data.init(e.player_index)
  player_data.refresh(player, storage.players[e.player_index])
end)

script.on_event(defines.events.on_player_removed, function(e)
  storage.players[e.player_index] = nil
end)

script.on_event(
  { defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed, defines.events.on_player_joined_game },
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

script.on_configuration_changed(function (e)
  -- Called when the mod is updated or the save is loaded
  if e.mod_changes and e.mod_changes["bot-insight"] then
    init_storages()
    for _, player in pairs(game.connected_players) do
      local player_table = storage.players[player.index]
      player_data.refresh(player, player_table)
    end
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if string.sub(e.setting, 1, 11) == "bot-insight" then
    local player = game.get_player(e.player_index)
    local player_table = storage.players[e.player_index]
    player_data.refresh(player, player_table)
  end
end)

-- TICK

-- count bots often, update the GUI less often
script.on_nth_tick(2, function()
    if storage.delivery_history == nil then
        init_storages()
    end
    bot_counter.count_bots(game)
    for _, player in pairs(game.connected_players) do
      controller_gui.update_window(player, storage.bot_items["logistic-robot"])
    end

    if game.tick % 60 == 0 then
      for _, player in pairs(game.connected_players) do
        local player_table = storage.players[player.index]
        bots_gui.update(player, player_table)
      end
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
    local player = game.get_player(e.player_index)
    if not player then
      return
    end
    local player_table = storage.players[e.player_index]
    if not player_table then
      return
    end
    player_table.bots_window.visible = player.controller_type ~= defines.controllers.cutscene
  end
)

script.on_event(defines.events.on_player_controller_changed, function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  local player_table = storage.players[e.player_index]
  if not player_table then
    return
  end
  bots_gui.update(player, player_table)
end)

script.on_event(
  { defines.events.on_gui_opened, defines.events.on_gui_closed },
  --- @param e EventData.on_gui_opened|EventData.on_gui_closed
  function(e)
    if e.gui_type ~= defines.gui_type.entity or e.entity.type ~= "locomotive" then
      return
    end

    local player = game.get_player(e.player_index)
    if not player then
      return
    end
    local player_table = storage.players[e.player_index]
    if not player_table then
      return
    end
    bots_gui.update(player, player_table)
  end
)
