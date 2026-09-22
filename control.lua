-- Main script for Logistics Insights mod

-- Optional benchmark override hook. Loaded BEFORE any scripts.* require so the
-- overrides (e.g. bench_profiler.enabled = true) are in place before scheduler.lua
-- captures debugger.PROFILING / bench_profiler.enabled at module load time.
-- The bench-overrides.lua file is gitignored and only present when the bench
-- harness is sweeping configurations. It returns a function that monkey-patches
-- accessor functions on global_data; that function is invoked further down,
-- after global_data is required.
local _bench_ok, _bench_overrides = pcall(require, "bench-overrides")

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local controller_gui = require("scripts.controller-gui")
local utils = require("scripts.utils")
local migrations = require("scripts.migrations")
local main_window = require("scripts.mainwin.main_window")
local scheduler = require("scripts.scheduler")
local networks_window= require("scripts.networkswin.networks_window")
local network_settings = require("scripts.networkswin.network_settings")
local tooltips_helper = require("scripts.tooltips-helper")
local analysis_coordinator = require("scripts.analysis-coordinator")
local scan_coordinator = require("scripts.scan-coordinator")
local events = require("scripts.events")
local bench_profiler = require("scripts.bench-profiler")

-- Apply bench-overrides accessor patches now that global_data is loaded.
-- The early require above already executed any module-load-time side effects
-- (e.g. setting bench_profiler.enabled = true) before scheduler was loaded.
if _bench_ok and type(_bench_overrides) == "function" then
  _bench_overrides(global_data)
end

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
  -- Apply setting overrides to the scheduler. Without this, the chunk interval
  -- and the per-player UI update interval silently have no effect until the
  -- user changes them in-game, because tasks are registered with hardcoded
  -- defaults at module load.
  scheduler.apply_global_settings()
  scheduler.apply_all_player_intervals()
end)

script.on_load(function()
  -- Re-apply scheduler interval overrides for existing saves. Tasks are
  -- registered fresh on every load with hardcoded intervals, and the
  -- overrides live outside storage, so both the global and the per-player
  -- ones have to be rebuilt here. Reads storage only, so safe in on_load.
  -- With the queue windows aligned to absolute ticks, this is what makes a
  -- joining client's schedule identical to everyone else's.
  scheduler.apply_global_settings()
  scheduler.apply_all_player_intervals()
end)

local PROFILING = debugger.PROFILING

local function full_UI_refresh(player, player_table)
  local p1, p2, p3, p4
  if PROFILING then p1 = helpers.create_profiler() end
  main_window.ensure_ui_consistency(player, player_table)
  if PROFILING then p1.stop() p2 = helpers.create_profiler() end
  controller_gui.update_window(player, player_table)
  if PROFILING then p2.stop() p3 = helpers.create_profiler() end
  main_window.update(player, player_table)
  if PROFILING then p3.stop() p4 = helpers.create_profiler() end
  networks_window.update(player)
  if PROFILING then
    p4.stop()
    log({"", "[perf] ui-update: ensure_consistency=", p1, " controller_gui=", p2, " main_window=", p3, " networks_window=", p4})
  end
end

-- SETTING UP AND HANDLING SCHEDULED EVENTS
-- All schedules are running every N ticks, where they are spaced out. The scheduler ensures that mostly only one task runs per tick.
-- 7: Bot chunk scanning. Set by the "Chunk interval" setting (3, 7, 13, 23, 37 or 53) through
--    scheduler.apply_global_settings. Lower tracks deliveries more closely, at more CPU
-- 5: "analysis-progress-update" to update progress bars
-- 7: Cell chunk scanning, and picking the next foreground network. Cells change less often.
-- 9: Run one step of the currently active derived analysis, if any.
-- 11: Background network refresh
-- 29: Check whether a player's active network has changed
-- 31: Pick next network to analyse for suggestions and undersupply
-- 60: UI update per player, set by the "UI update interval" setting

--- Check whether a player's active network has changed, and if so, reprioritise scanning and refresh the UI
--- @param player LuaPlayer
--- @param player_table PlayerData
local function network_check(player, player_table)
  if network_data.check_network_changed(player, player_table) then
    -- The exclusion lists on screen belong to the old network: draw the new one's
    player_table.ignored_storages_for_mismatch_shown = 0
    player_table.ignored_trips_shown = 0
    -- The old network's generation counters, and its trip on the map, mean nothing here
    player_data.invalidate_ui_state(player_table)
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
-- Drop the delivery history of networks nobody has watched for a while. Swept every 20 seconds, so
-- the grace period is never overshot by much
scheduler.register({ name = "expire-unobserved-history", interval = 20*60, is_heavy = false, per_player = false,
  fn = network_data.expire_unobserved_history
})

-- When the bench harness has enabled the in-memory profiler, dump accumulated
-- per-task counts and times once per second. This is the only output during a
-- benchmark run; the harness reads the highest-tick dump from factorio-current.log.
if bench_profiler.enabled then
  scheduler.register({ name = "bench-profiler-dump", interval = 60, is_heavy = false, per_player = false,
    fn = bench_profiler.dump
  })
end

-- Scheduler tasks for refreshing the foreground networks
scheduler.register({ name = "find-next-player-network", interval = 7, is_heavy = false, per_player = false, fn =
  scan_coordinator.initiate_next_player_network_scan
})
-- Registered at the setting's default; apply_global_settings re-points it at the actual setting
scheduler.register({ name = scheduler.BOT_CHUNK_TASK, interval = 7, is_heavy = true, per_player = false, fn = function()
  if storage.fg_refreshing_network_id then
    scan_coordinator.foreground_bot_chunk(storage.fg_refreshing_network_id)
  end
end})
scheduler.register({ name = "player-network-cell-chunk", interval = 7, is_heavy = true, per_player = false, fn = function()
  if storage.fg_refreshing_network_id then
    scan_coordinator.foreground_cell_chunk(storage.fg_refreshing_network_id)
  end
end})

-- Scheduler task for analysis tasks that derive from bots and cells data
scheduler.register({ name = "pick-network-to-analyse", interval = 31, per_player = false, is_heavy = false, fn = function()
  local nwd = analysis_coordinator.find_network_to_analyse()
  if nwd then
    debugger.info("Analysing network ID " .. nwd.id)
    analysis_coordinator.start_analysis(nwd)
  end
end })

-- Scheduler task for running the currently active derived analysis, if any
scheduler.register({ name = "run-derived-analysis", interval = 9, per_player = false, is_heavy = true,
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
  local profiler
  if PROFILING then profiler = helpers.create_profiler() end
  scheduler.on_tick()
  if PROFILING then
    profiler.stop()
    log({"", "[perf] tick ", profiler})
  end
end)

-- Called when a new player is created
script.on_event({ defines.events.on_player_created },
  --- @param e EventData.on_player_created
  function(e)
    local player = game.get_player(e.player_index)
    if player then
      player_data.init(e.player_index)
      local player_table = storage.players[e.player_index]
      player_data.update_settings(player, player_table)
      controller_gui.create_window(player) -- Needs the settings, so after them
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
    -- Every peer sees this at the same tick, so every peer rebuilds the same queue with the new
    -- player's tasks in it, rather than only the peers that build their next window later
    scheduler.invalidate_queue()
    local player_table = player_data.get_player_table(e.player_index)
    if player_table and player_table.network and player_table.network.valid then
      network_data.player_changed_networks(player_table, nil, player_table.network)
    end
  end)

-- Called when a player is deleted/removed from the game
script.on_event(defines.events.on_player_removed,
  --- @param e EventData.on_player_removed
  function(e)
  storage.players[e.player_index] = nil
  scheduler.clear_player_intervals(e.player_index)
  -- Reset cached references as player configuration has changed
  network_data.remove_player_index(e.player_index)
end)

script.on_event(defines.events.on_player_left_game,
  --- @param e EventData.on_player_left_game
  function(e)
  scheduler.invalidate_queue() -- As on join: drop their tasks on every peer at once
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
  migrations.on_config_changed(e)
  -- Re-apply scheduler interval overrides after config change. Mod version
  -- upgrades may register new tasks or change defaults; this ensures the
  -- interval settings still take effect.
  scheduler.apply_global_settings()
  scheduler.apply_all_player_intervals()
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
      elseif e.setting == "li-ignore-mobile-trips" and global_data.ignore_mobile_trips() then
        -- Switched on: take the listed trips to players and spidertrons off at once. Switched
        -- off, they come back as they are made, like a destination taken off the ignore list
        network_data.purge_mobile_trips()
      elseif e.setting == "li-chunk-size-global" then
        -- Nothing to do: a chunker reads the size when its next pass starts. Cutting the running
        -- pass short would publish half a scan as a whole one, recording every unscanned bot's
        -- delivery as finished
      elseif e.setting == "li-chunk-processing-interval-ticks" then
        -- Re-point the bot chunk task at the new interval
        scheduler.apply_global_settings()
      elseif e.setting == "li-calculate-undersupply" then
        if not global_data.calculate_undersupply() then
          -- Drop what was calculated before, so the mini window and Networks window stop counting it
          for _, nwd in pairs(storage.networks) do
            if nwd.suggestions then nwd.suggestions:set_cached_list("undersupply", nil) end
          end
        end
        -- The row comes and goes with this global setting, so every player's window has to be
        -- rebuilt, not just the one who changed it. From the console there is no player at all
        for player_index, _ in pairs(storage.players) do
          events.emit(events.on_recreate_main_window, player_index)
        end
      end
      -- The other global settings are read from the cache when next used
    else
      -- Per-player setting change
      local player = game.get_player(e.player_index)
      local player_table = player_data.get_player_table(e.player_index)
      if player and player_table then
        if e.setting == "li-highlight-duration" or e.setting == "li-initial-zoom" then
          -- Read straight from player.mod_settings when a highlight is drawn, so nothing to cache
        elseif e.setting == "li-ui-update-interval" or e.setting == "li-show-trip-estimates" then
          -- Cached, and picked up on the next update
          player_data.update_settings(player, player_table)
          if e.setting == "li-ui-update-interval" then
            scheduler.apply_player_intervals(e.player_index, player_table)
          end
        elseif e.setting == "li-show-history" then
          -- Show History was enabled or disabled
          player_data.update_settings(player, player_table)
          events.emit(events.on_recreate_main_window, e.player_index)
        elseif e.setting == "li-show-main-mini-window" or e.setting == "li-show-networks-mini-window" then
          -- Recreate the mini windows (or not), depending on settings
          player_data.update_settings(player, player_table)
          controller_gui.create_window(player)
        else
          -- For other settings, rebuild the main window
          player_data.update_settings(player, player_table)
          events.emit(events.on_recreate_main_window, e.player_index)
        end
      end
    end
  end
end)


-- CONTROLLER

script.on_event(defines.events.on_gui_click,
  --- @param event EventData.on_gui_click
  function(event)
  -- Call the various GUI handlers in turn, stopping if one of them handles the event
  if controller_gui.onclick(event) then return end
  if main_window.onclick(event) then return end
  if network_settings.on_gui_click(event) then return end
  networks_window.on_gui_click(event)
end)

-- PIPETTE SUPPORT: track hovered element and handle Q-key pickup

script.on_event(defines.events.on_gui_hover, function(event)
  local element = event.element
  if element and element.valid and element.type == "sprite-button" and
     element.sprite and element.sprite:find("^item/") then
    local pt = player_data.get_player_table(event.player_index)
    if pt then pt.hovered_element = element end
  end
end)

script.on_event(defines.events.on_gui_leave, function(event)
  local pt = player_data.get_player_table(event.player_index)
  if pt then pt.hovered_element = nil end
end)

script.on_event("logistics-insights-pipette", function(event)
  local pt = player_data.get_player_table(event.player_index)
  if not pt or not pt.hovered_element then return end
  local element = pt.hovered_element
  if not element.valid then pt.hovered_element = nil; return end
  local item_name = element.sprite and element.sprite:match("^item/(.+)$")
  if not item_name then return end
  local quality_name = (element.quality and element.quality.name) or "normal"
  local player = game.get_player(event.player_index)
  if player and player.valid then
    player.clear_cursor()
    player.cursor_ghost = {name = item_name, quality = quality_name}
  end
end)

--- The settings window closed. Update the setting button in the main window
script.on_event({events.on_settings_pane_closed},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    main_window.update(player, player_table)
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
    main_window.update(player, player_table)
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

script.on_event({events.on_recreate_main_window},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    -- Creating the window first destroys it if it already exists
    main_window.create(player, player_table)
  end
end)

script.on_event({events.on_suggestions_changed},
  ---@param e {player_index: uint}
  function(e)
  local player = game.get_player(e.player_index)
  local player_table = player_data.get_player_table(e.player_index)
  if player and player.valid and player_table then
    main_window.update(player, player_table)
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
    main_window.update(player, player_table)
  end
end)

script.on_event(
  { defines.events.on_gui_opened, defines.events.on_gui_closed },
  --- @param e EventData.on_gui_opened|EventData.on_gui_closed
  function(e)
    -- Close our windows when the player presses E or ESC (via player.opened)
    if e.name == defines.events.on_gui_closed and e.gui_type == defines.gui_type.custom and e.element then
      local name = e.element.name
      if name == main_window.WINDOW_NAME or name == networks_window.WINDOW_NAME then
        local player = game.get_player(e.player_index)
        if not player or not player.valid then return end
        local player_table = player_data.get_player_table(e.player_index)
        if not player_table then return end

        -- Pinned windows ignore E/ESC
        local is_pinned = (name == main_window.WINDOW_NAME and player_table.main_window_pinned)
          or (name == networks_window.WINDOW_NAME and player_table.networks_window_pinned)
        if is_pinned then return end

        -- Unpinned: close the window
        if name == main_window.WINDOW_NAME then
          main_window.set_window_visible(player, player_table, false)
        else
          networks_window.set_window_visible(player, player_table, false)
        end
        return
      end
    end

    -- Show/hide the GUI when the player opens a locomotive view
    if e.gui_type ~= defines.gui_type.entity or not e.entity or e.entity.type ~= "locomotive" then
      return
    end
    local player = game.get_player(e.player_index)
    local player_table = player_data.get_player_table(e.player_index)

    if player and player.valid and player_table then
      main_window.update(player, player_table)
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

  local g = player.gui and player.gui.screen
  local window = g and g.logistics_insights_window
  if window then
    -- A space platform has no logistic network, so nothing to show there
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

-- INTEGRATION TESTING (only active when factorio-test mod is present)
if script.active_mods["factorio-test"] then
  require("__factorio-test__/init")({
    "tests.integration.basic_network_itest",
  }, {
    game_speed = 1000,
    default_timeout = 60 * 60 * 5,  -- 18000 ticks
    load_luassert = true,
  })
end
