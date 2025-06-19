local player_data = require("scripts.player-data")
local bots_gui = require("scripts.bots-gui")

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
  init_storages()
end)

-- PLAYER

script.on_event(defines.events.on_player_created, function(e)
  local player = game.get_player(e.player_index)
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

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if string.sub(e.setting, 1, 11) == "bot-insight" then
    local player = game.get_player(e.player_index)
    local player_table = storage.players[e.player_index]
    player_data.refresh(player, player_table)
  end
end)

-- TICK

local function count_bots(game)
    storage.bot_items = {}
    storage.bot_deliveries = {}
    if storage.bot_active_deliveries == nil then
        storage.bot_active_deliveries = {}
    end
    local logi_bots = 0
    local con_bots = 0
    for _, player in pairs(game.players) do
        if player then
            local network = player.force.find_logistic_network_by_position(player.position, player.surface)
            if network then
                logi_bots = logi_bots + network.available_logistic_robots
                con_bots = con_bots + network.available_construction_robots
                for _, bot in ipairs(network.logistic_robots) do
                    if bot.valid and bot.robot_order_queue then
                        for _, order in pairs(bot.robot_order_queue) do
                            -- Record order, deliver, etc
                            storage.bot_items[order.type] = (storage.bot_items[order.type] or 0) + 1
                            local item_name = order.target_item.name.name
                            local item_count = order.target_count
                            local quality = order.target_item.quality.name
                            local key = item_name .. "-" .. quality
                            -- For Deliveries, record the item 
                            if order.type == defines.robot_order_type.deliver and item_name then
                                if storage.bot_deliveries[key] == nil then
                                    storage.bot_deliveries[key] = {
                                        item_name = item_name,
                                        quality_name = quality,
                                        count = item_count,
                                    }
                                else
                                    storage.bot_deliveries[key].count = storage.bot_deliveries[key].count + item_count
                                end
                                if storage.bot_active_deliveries[bot.unit_number] == nil then
                                    -- Order not seen before
                                    storage.bot_active_deliveries[bot.unit_number] = {
                                        item_name = item_name,
                                        quality_name = quality,
                                        count = item_count,
                                        first_seen = game.tick,
                                        last_seen = game.tick,
                                    }
                                else -- It's still under way
                                    storage.bot_active_deliveries[bot.unit_number].last_seen = game.tick
                                end
                            end
                            break -- only count the first order 
                        end
                    end
                end
            end
        end
    end
    -- Remove orders no longer active from the list and add to history
    for unit_number, order in pairs(storage.bot_active_deliveries) do
        if order.last_seen < game.tick then
            key = order.item_name..order.quality_name
            if storage.delivery_history[key] == nil then
                storage.delivery_history[key] = {
                    item_name = order.item_name,
                    quality_name = order.quality_name,
                    count = 0,
                    ticks = 0,
                }
            end
            history_order = storage.delivery_history[key]
            history_order.count = (history_order.count or 0) + order.count
            ticks = order.last_seen - order.first_seen
            if ticks < 1 then ticks = 1 end
            history_order.ticks = (history_order.ticks or 0) + ticks
            history_order.avg = history_order.ticks / history_order.count
            storage.bot_active_deliveries[unit_number] = nil -- remove from active list
        end
    end
    storage.bot_items["logistic-robot"] = logi_bots
    storage.bot_items["construction-robot"] = con_bots
end

-- count bots often, update the GUI less often
script.on_nth_tick(2, function()
    if storage.delivery_history == nil then
        init_storages()
    end
    -- count the bots
    count_bots(game)

    -- update the GUI every second
    if game.tick % 60 == 0 then
      for _, player in pairs(game.connected_players) do
        local player_table = storage.players[player.index]
        bots_gui.update(player, player_table)
      end
    end
end)

-- CONTROLLER

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
