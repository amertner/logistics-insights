-- Main script for Logistics Insights mod
local flib_migration = require("__flib__.migration")

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local bot_counter = require("scripts.bot-counter")
local logistic_cell_counter = require("scripts.logistic-cell-counter")
local controller_gui = require("scripts.controller-gui")
local utils = require("scripts.utils")
local li_migrations = require("scripts.migrations")
local main_window = require("scripts.mainwin.main_window")
local scheduler = require("scripts.scheduler")
local networks_window= require("scripts.networkswin.networks_window")
local network_settings = require("scripts.networkswin.network_settings")
local tooltips_helper = require("scripts.tooltips-helper")
local analysis_coordinator = require("scripts.analysis-coordinator")
local scan_coordinator = require("scripts.scan-coordinator")
local events = require("scripts.events")

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
  global_data.init()
  player_data.init_storages()
  network_data.init()
end)

local function full_UI_refresh(player, player_table)
  main_window.ensure_ui_consistency(player, player_table)
  controller_gui.update_window(player, player_table)
  main_window.update(player, player_table, false)
  networks_window.update(player)
end

-- SETTING UP AND HANDLING SCHEDULED EVENTS
-- All schedules are running every N ticks, where they are spaced out. The scheduler ensures that mostly only one task runs per tick.
-- 3: Bot chunk scanning. Fast, to reduce undercounting. (Can be 3, 7, 13, 23, 37, 53)
-- 5: Run one step of the currently active derived analysis, if any.
-- 7: "analysis-progress-update" to update progress bars
-- 11: Background network refresh
-- 29: Check whether a player's active network has changed
-- 31: Pick next network to analyse for suggestions and undersupply
-- 59: Cell chunk scanning. Slower is ok, as cells change less often. (Can be 17, 37, 41, 53, 59, 71, 89)
-- 61: Check which derived analysis should run, if any

--- Check whether a player's active network has changed, and if so, reprioritise scanning and refresh the UI
--- @param player LuaPlayer
--- @param player_table PlayerData
local function network_check(player, player_table)
  if network_data.check_network_changed(player, player_table) then
    player_table.ignored_storages_for_mismatch_shown = 0
    scan_coordinator.prioritise_scanning_new_player_network(player_table)
    main_window.clear_progress(player_table)
    full_UI_refresh(player, player_table)
  end
end

-- Check whether a player's active network has changed
scheduler.register({ name = "network-check", interval = 29, per_player = true, is_heavy = false, fn = function(player, player_table)
  network_check(player, player_table)
end })
-- Scheduler for refreshing background networks that don't have an active player in them
scheduler.register({ name = "background-refresh", interval = 11, is_heavy = true, per_player = false,
  fn = scan_coordinator.background_refresh
})
-- Clear the tooltip caches every 10 minutes to avoid memory bloat
scheduler.register({ name = "clear-caches", interval = 60*10, is_heavy = false, per_player = false,
  fn = tooltips_helper.clear_caches
})

-- Scheduler tasks for refreshing the foreground networks
scheduler.register({ name = "find-next-player-network", interval = 7, is_heavy = false, per_player = false, fn =
  scan_coordinator.initiate_next_player_network_scan
})
scheduler.register({ name = "player-network-bot-chunk", interval = 7, is_heavy = true, per_player = false, fn = function()
  if storage.fg_refreshing_network_id then
    scan_coordinator.foreground_bot_chunk(storage.fg_refreshing_network_id)
  end
end})
scheduler.register({ name = "player-network-cell-chunk", interval = 7, is_heavy = true, per_player = false, fn = function()
  if storage.fg_refreshing_network_id then
    scan_coordinator.foreground_cell_chunk(storage.fg_refreshing_network_id)
  end
end})

-- scheduler.register({ name="show-li-alerts", interval=61, is_heavy=false, per_player=true, fn=function(player, player_table)
--   alerts_manager.show_alerts(player, player_table)
-- end })

-- Scheduler task for analysis tasks that derive from bots and cells data
scheduler.register({ name = "pick-network-to-analyse", interval = 31, per_player = false, is_heavy = false, fn = function()
  local nwd = analysis_coordinator.find_network_to_analyse()
  if nwd then
    debugger.info("Analysing network ID " .. nwd.id)
    analysis_coordinator.start_analysis(nwd)
  end
end })

-- Scheduler task for running the currently active derived analysis, if any
scheduler.register({ name = "run-derived-analysis", interval = 5, per_player = false, is_heavy = true,
  fn = analysis_coordinator.run_analysis_step })

-- Schedulers for updating the UI
scheduler.register({ name = "ui-update", interval = 60, per_player = true, is_heavy = false,
  fn = full_UI_refresh })

-- Update just progress indicators for background scans
scheduler.register({ name = "analysis-progress-update", interval = 5, per_player = true, is_heavy = false, fn = function(player, player_table)
  if analysis_coordinator.is_analysing_player_network(player_table) then
    local state = storage.analysis_state
    if state and state.undersupply_chunker then
      local progress = state.undersupply_chunker:get_progress()
      main_window.update_undersupply_progress(player_table, progress)
    end
    if state and state.storage_chunker then
      local progress = state.storage_chunker:get_progress()
      main_window.update_suggestions_progress(player_table, progress)
    end
  end
end })

-- All actual timed dispatching handler in scheduler.lua
script.on_nth_tick(1, function()
  scheduler.on_tick()
end)

-- Called when a new player is created
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
        networks_window.set_window_visible(player, player_table, player_table.networks_window_visible)
      end
    end
  end)

-- Called when an existing player joins a multiplayer game
script.on_event({ defines.events.on_player_joined_game },
  --- @param e EventData.on_player_joined_game
  function(e)
    local player_table = player_data.get_player_table(e.player_index)
    if player_table and player_table.network then
      network_data.player_changed_networks(player_table, nil, player_table.network)
    end
  end)

-- Called when a player is deleted/removed from the game
script.on_event(defines.events.on_player_removed,
  --- @param e EventData.on_player_removed
  function(e)
  storage.players[e.player_index] = nil
  -- Reset cached references as player configuration has changed
  player_data.reset_cache()
  network_data.remove_player_index(e.player_index)
end)

script.on_event(defines.events.on_player_left_game,
  --- @param e EventData.on_player_left_game
  function(e)
  network_data.remove_player_index(e.player_index)
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

      local center_if_offscreen = function(window)
        if window and window.valid then
          if window.location.x < -10 or window.location.x > player.display_resolution.width - 10 then
            window.location.x = player.display_resolution.width / 2
          end
          if window.location.y < -10 or window.location.y > player.display_resolution.height - 10 then
            window.location.y =(player.display_resolution.height) / 2
          end
        end
      end
      -- This shouldn't happen, but in case it does...
      center_if_offscreen(player.gui.screen.logistics_insights_window)
      center_if_offscreen(player.gui.screen.li_networks_window)
    end
  end
)

-- SETTINGS

script.on_configuration_changed(
  --- @param e ConfigurationChangedData
  function(e)

  -- Run migrations if the mod version has changed
  global_data.init()
  flib_migration.on_config_changed(e, li_migrations)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed,
  --- @param e EventData.on_runtime_mod_setting_changed
  function(e)
  if utils.starts_with(e.setting, "li-") then
    if e.setting_type == "runtime-global" then
      -- Global setting change
      global_data.settings_changed()
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
        scheduler.apply_global_settings()
        scheduler.apply_all_player_intervals()
      elseif e.setting == "li-gather-quality-data-global" or e.setting == "li-ignore-player-demands-in-undersupply" then
        -- Nothing particular to do yet; will be used on next chunking cycle
      end
    else
      -- Per-player setting change
      local player = game.get_player(e.player_index)
      local player_table = player_data.get_player_table(e.player_index)
      if player and player_table then
        if e.setting == "li-ui-update-interval" or
           e.setting == "li-highlight-duration" then
          -- These settings will be adapted dynamically
          player_data.update_settings(player, player_table)
          if e.setting == "li-ui-update-interval" then
            scheduler.apply_player_intervals(e.player_index, player_table)
          end
        elseif e.setting == "li-show-history" then
          -- Show History was enabled or disabled
          player_data.update_settings(player, player_table)
          main_window.destroy(player, player_table)
          main_window.create(player, player_table)
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
  if network_settings.on_gui_click(event) then return end
  local action = networks_window.on_gui_click(event)
  if action then
    local player = game.get_player(event.player_index)
    local player_table = player_data.get_player_table(event.player_index)
    if action == "refresh" then
      full_UI_refresh(player, player_table)
    end
  end
end)

--- The settings window closed. Update the setting button in the main window
script.on_event({events.on_settings_pane_closed},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    main_window.update(player, player_table, false)
  end
end)

-- The network has changed. Bring to foreground and refresh the main window.
script.on_event({events.on_forced_network_changed},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    network_check(player, player_table)
    main_window.set_window_visible(player, player_table, true)
    main_window.update(player, player_table, false)
  end
end)

-- An item was added to an ignore list, so the network settings window should be refreshed
script.on_event({events.on_ignorelist_changed},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    network_settings.update(player, player_table)
  end
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

-- When a window is moved, remember its location
script.on_event(defines.events.on_gui_location_changed,
  ---@param event EventData.on_gui_location_changed
  function(event)
    local player_table = player_data.get_player_table(event.player_index)
    if event.element and player_table then
      main_window.gui_location_moved(event.element, player_table)
      networks_window.gui_location_moved(event.element, player_table)
    end
end)
