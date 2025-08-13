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

-- SETTING UP AND HANDLING SCHEDULED EVENTS

-- Register periodic tasks with default intervals. Can be overridden with settings
scheduler.register({
  name = "network-check", interval = 30, per_player = false, fn = function(player, player_table)
    if player_data.check_network_changed(player, player_table) then
      bot_counter.network_changed(player, player_table)
      logistic_cell_counter.network_changed(player, player_table)
    end
  end })
scheduler.register({ name = "bot-chunk", interval = 10, per_player = true, capability = "delivery", fn = function(player, player_table)
    local bot_progress = bot_counter.gather_bot_data(player, player_table)
    main_window.update_bot_progress(player_table, bot_progress)
  end })
scheduler.register({ name = "cell-chunk", interval = 60, per_player = true, capability = "activity", fn = function(player, player_table)
    local cells_progress = logistic_cell_counter.gather_data(player, player_table)
    main_window.update_cells_progress(player_table, cells_progress)
  end })
scheduler.register({ name = "ui-update", interval = 60, per_player = true, fn = function(player, player_table)
    main_window.ensure_ui_consistency(player, player_table)
    controller_gui.update_window(player, player_table)
    main_window.update(player, player_table, false)
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
    local player = game.get_player(e.player_index)
    local player_table = player_data.get_player_table(e.player_index)
    if player and player_table then
      -- Special handling for mini window setting
      if e.setting == "li-show-mini-window" then
        controller_gui.update_window(player, player_table)
      elseif e.setting == "li-chunk-size" then
        -- Adopt and cache the updated setting
        player_data.update_settings(player, player_table)
        -- Process (partial) data and start gathering with new chunk size
        bot_counter.restart_counting(player_table)
        logistic_cell_counter.restart_counting(player_table)
      elseif e.setting == "li-chunk-processing-interval" or
            e.setting == "li-ui-update-interval" or
            e.setting == "li-pause-for-bots" or
            e.setting == "li-highlight-duration" then
        -- These settings will be adapted dynamically
        player_data.update_settings(player, player_table)
        if e.setting == "li-chunk-processing-interval" or e.setting == "li-ui-update-interval" then
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
end)


-- CONTROLLER

script.on_event(defines.events.on_gui_click,
  --- @param event EventData.on_gui_click
  function(event)
  controller_gui.onclick(event)
  main_window.onclick(event)
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
