-- Main script for Logistics Insights mod
local flib_migration = require("__flib__.migration")

local player_data = require("scripts.player-data")  
local network_data = require("scripts.network-data")
local bot_counter = require("scripts.bot-counter")
local logistic_cell_counter = require("scripts.logistic-cell-counter")
local controller_gui = require("scripts.controller-gui")
local utils = require("scripts.utils")
local li_migrations = require("scripts.migrations")
local progress_bars = require("scripts.mainwin.progress_bars")
local main_window = require("scripts.mainwin.main_window")
local scheduler = require("scripts.scheduler")
local capability_manager = require("scripts.capability-manager")
local networks_window= require("scripts.networkswin.networks_window")

---@alias SurfaceName string

---@class ResultLocationData
---@field position MapPosition
---@field surface SurfaceName
---@field items LuaEntity[]

-- STORAGE

script.on_init(
  --- @param e EventData
  function(e)
  -- Called when the mod is first added to a save
  player_data.init_storages()
end)

-- Called often to refresh background networks. Do at most one chunk of work per call.
local function background_refresh()
  if storage.bg_refreshing_network_id then
    -- We're refreshing a network already
    local networkdata = network_data.get_networkdata_fromid(storage.bg_refreshing_network_id)
    if networkdata then
      if bot_counter.is_background_done(networkdata) then        
        -- The bot counter is finished; process the logistic cells
        if logistic_cell_counter.is_background_done(networkdata) then
          local network = network_data.get_LuaNetwork(networkdata)
          if network then
            local waiting_to_charge_count = (networkdata.bot_items and networkdata.bot_items["waiting-for-charge-robot"]) or 0
            -- Evaluate cells and bots for suggestions
            networkdata.suggestions:evaluate_background_cells(network, waiting_to_charge_count)
            networkdata.suggestions:evaluate_background_bots(network)

            -- Evaluate undersupply as the final step
            networkdata.suggestions:evaluate_background_undersupply(network, networkdata.bot_deliveries)
          end
          -- Signal that the background refresh is done
          storage.bg_refreshing_network_id = nil
        else
          logistic_cell_counter.process_background_network(networkdata)
        end
      else
        bot_counter.process_background_network(networkdata)
      end
    end
  else
    -- No background network is being refreshed; find one to refresh
    local networkdata = network_data.get_next_background_network()
    if networkdata then
      local network = network_data.get_LuaNetwork(networkdata)
      if network then
        storage.bg_refreshing_network_id = networkdata.id
        bot_counter.init_background_processing(networkdata, network)
        logistic_cell_counter.init_background_processing(networkdata, network)
      end
    end
  end
end

-- SETTING UP AND HANDLING SCHEDULED EVENTS

-- Check whether a player's active network has changed
scheduler.register({
name = "network-check", interval = 30, per_player = true, fn = function(player, player_table)
  if network_data.check_network_changed(player, player_table) then
    bot_counter.network_changed(player, player_table)
    logistic_cell_counter.network_changed(player, player_table)
    networks_window.update_network_count(player, table_size(storage.networks) or 0)
  end
end })
-- Scheduler for refreshing background networks that don't have an active player in them
scheduler.register({ name = "background-refresh", interval = 10, per_player = false,
  fn = background_refresh
})

-- Scheduler tasks for refreshing the foreground network for each player
scheduler.register({ name = "player-bot-chunk", interval = 10, per_player = true, capability = "delivery", fn = function(player, player_table)
  local bot_progress = bot_counter.gather_data_for_player_network(player, player_table)
  main_window.update_bot_progress(player_table, bot_progress)
  -- Mark suggestions & undersupply capabilities dirty (they both depend on bot data)
  capability_manager.mark_dirty(player_table, "suggestions")
  capability_manager.mark_dirty(player_table, "undersupply")
end })
scheduler.register({ name = "player-cell-chunk", interval = 60, per_player = true, capability = "activity", fn = function(player, player_table)
  local cells_progress = logistic_cell_counter.gather_data_for_player_network(player, player_table)
  main_window.update_cells_progress(player_table, cells_progress)
  capability_manager.mark_dirty(player_table, "suggestions")
end })

-- Scheduler tasks for undersupply and suggestions
scheduler.register({ name = "undersupply-bots", interval = 60, per_player = true, capability = "undersupply", fn = function(player, player_table)
  local nwd = network_data.get_networkdata(player_table.network)
  if nwd then
    local bot_deliveries = nwd.bot_deliveries or {}
    nwd.suggestions:evaluate_player_undersupply(player_table, bot_deliveries, false)
  end
end })
scheduler.register({ name = "suggestions-cells", interval = 60, per_player = true, capability = "suggestions", fn = function(player, player_table)
  local nwd = network_data.get_networkdata(player_table.network)
  if nwd then
    local waiting_to_charge_count = (nwd.bot_items and nwd.bot_items["waiting-for-charge-robot"]) or 0
    -- Evaluate cells and bots for suggestions
    nwd.suggestions:evaluate_player_cells(player_table, waiting_to_charge_count)
  end
end })
scheduler.register({ name = "suggestions-bots", interval = 60, per_player = true, capability = "suggestions", fn = function(player, player_table)
  local nwd = network_data.get_networkdata(player_table.network)
  if nwd then
    nwd.suggestions:evaluate_player_bots(player_table)
  end
end })

-- Scheduler for updating the UI
scheduler.register({ name = "ui-update", interval = 60, per_player = true, fn = function(player, player_table)
  main_window.ensure_ui_consistency(player, player_table)
  controller_gui.update_window(player, player_table)
  main_window.update(player, player_table, false)
  networks_window.update(player)
end })

-- All actual timed dispatching handler in scheduler.lua
script.on_nth_tick(1, function()
  scheduler.on_tick()
end)

-- Called when a new player joins the game
script.on_event({ defines.events.on_player_created },
  --- @param e EventData.on_player_created
  function(e)
    local player = game.get_player(e.player_index)
    if player then
      controller_gui.create_window(player)
      player_data.init(e.player_index)
      local player_table = storage.players[e.player_index]
      player_data.update_settings(player, player_table)
      if player_table then
        scheduler.apply_player_intervals(e.player_index, player_table)
      end
      if player_table and player then
        main_window.set_window_visible(player, player_table, player_table.bots_window_visible)
      end
    end
  end)

script.on_event(defines.events.on_player_removed,
  --- @param e EventData.on_player_removed
  function(e)
  storage.players[e.player_index] = nil
  -- Reset cached references as player configuration has changed
  player_data.reset_cache()
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
      main_window.update(player, player_table, false)
    end
  end
)

-- SETTINGS

script.on_configuration_changed(
  --- @param e ConfigurationChangedData
  function(e)

  -- Remove all prior information since it may refer to modded items that are no longer available
  -- #TODO Figure out how to do this in a good way. If mods were removed or upgraded, we may have dud info, but just clearing network data means that the storage.network isn't initialised for the players' current networks either, which is bad.
  --network_data.init()

  -- Run migrations if the mod version has changed
  flib_migration.on_config_changed(e, li_migrations)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed,
  --- @param e EventData.on_runtime_mod_setting_changed
  function(e)
  if utils.starts_with(e.setting, "li-") then
    if e.setting_type == "runtime-global" then
      -- Global setting change
      if e.setting == "li-show-all-networks" then
        -- When this setting is changed, potentially purge unobserved networks and refresh the UI
        network_data.purge_unobserved_networks()
      elseif e.setting == "li-chunk-size-global" then
        -- Process (partial) data and start gathering with new chunk size on all networks
        for _, nwd in pairs(storage.networks) do
          bot_counter.restart_counting(nwd)
          logistic_cell_counter.restart_counting(nwd)
        end
      elseif e.setting == "li-chunk-processing-interval-ticks" then
        -- Update the global bot chunk interval setting
        -- #TODO: Add a way to apply this global setting
        --scheduler.apply_player_intervals(e.player_index, player_table)
        --scheduler.update_interval("chunk-interval", e.value)
      elseif e.setting == "li-gather-quality-data-global" then
      end
    else
      -- Per-player setting change
      local player = game.get_player(e.player_index)
      local player_table = player_data.get_player_table(e.player_index)
      if player and player_table then
        if e.setting == "li-show-mini-window" then
          -- Special handling for mini window setting
          controller_gui.update_window(player, player_table)
        elseif e.setting == "li-ui-update-interval" or
              e.setting == "li-pause-for-bots" or
              e.setting == "li-highlight-duration" then
          -- These settings will be adapted dynamically
          player_data.update_settings(player, player_table)
          if e.setting == "li-ui-update-interval" then
            scheduler.apply_player_intervals(e.player_index, player_table)
          end
        elseif e.setting == "li-show-history" then
          -- Show History was enabled or disabled
          player_data.update_settings(player, player_table)
          if player_table.settings.show_history then
            -- Show History was enabled, so resume the history timer if it was paused
            player_table.history_timer:resume()
          end
        elseif e.setting == "li-pause-while-hidden" then
          -- Pause while hidden setting was changed
          local flicker_window = not player_table.bots_window_visible
          if flicker_window then
            -- Show the window, so related things can update. Very messy.
            main_window.set_window_visible(player, player_table, true)
          end
          player_data.update_settings(player, player_table)
          if flicker_window then
            -- Re-hide the window
            main_window.set_window_visible(player, player_table, false)
          end
        else
          -- For other settings, rebuild the main window
          player_data.update_settings(player, player_table)
          main_window.destroy(player, player_table)
          main_window.create(player, player_table)
        end
      end
    end
  end
end)


-- CONTROLLER

script.on_event(defines.events.on_gui_click,
  --- @param event EventData.on_gui_click
  function(event)
  controller_gui.onclick(event)
  main_window.onclick(event)
  networks_window.on_gui_click(event)
end)

script.on_event(
  { defines.events.on_cutscene_started, defines.events.on_cutscene_finished, defines.events.on_cutscene_cancelled },
  --- @param e EventData.on_cutscene_started|EventData.on_cutscene_finished|EventData.on_cutscene_cancelled
  function(e)
    -- Hide the bots window when a cutscene starts, show it again when it ends
    local player = game.get_player(e.player_index)
    local player_table = player_data.get_player_table(e.player_index)

    if player and player_table and player_table.bots_window_visible then
      main_window.set_window_visible(player, player_table, player.controller_type ~= defines.controllers.cutscene)
    end
  end
)

script.on_event(defines.events.on_player_controller_changed,
  --- @param e EventData.on_player_controller_changed
  function(e)
  local player = game.get_player(e.player_index)
    local player_table = player_data.get_player_table(e.player_index)

  if player and player.valid and player_table then
    main_window.update(player, player_table, false)
  end
end)

script.on_event(
  { defines.events.on_gui_opened, defines.events.on_gui_closed },
  --- @param e EventData.on_gui_opened|EventData.on_gui_closed
  function(e)
    -- Show/hide the GUI when the player opens a locomotive view
    if e.gui_type ~= defines.gui_type.entity or e.entity.type ~= "locomotive" then
      return
    end
    local player = game.get_player(e.player_index)
    local player_table = player_data.get_player_table(e.player_index)

    if player and player.valid and player_table then
      main_window.update(player, player_table, false)
    end
  end
)

script.on_event(defines.events.on_player_changed_surface,
  --- @param e EventData.on_player_changed_surface
  function(e)
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
