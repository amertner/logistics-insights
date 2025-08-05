-- Main window coordinator for the logistics insights GUI
-- Handles window creation, layout, and coordination between different row types

local main_window = {}

local player_data = require("scripts.player-data")
local utils = require("scripts.utils")
local game_state = require("scripts.game-state")
local pause_manager = require("scripts.pause-manager")
local mini_button = require("scripts.mainwin.mini_button")
local find_and_highlight = require("scripts.mainwin.find_and_highlight")
local progress_bars = require("scripts.mainwin.progress_bars")
local delivery_row = require("scripts.mainwin.delivery_row")
local history_rows = require("scripts.mainwin.history_rows")
local activity_row = require("scripts.mainwin.activity_row")
local network_row = require("scripts.mainwin.network_row")
local undersupply_row = require("scripts.mainwin.undersupply_row")
local suggestions_row = require("scripts.mainwin.suggestions_row")

-------------------------------------------------------------------------------
-- Create main window and all rows needed based on settings
-------------------------------------------------------------------------------

local WINDOW_NAME = "logistics_insights_window"

--- Create the main Logistics Insights window
--- @param player LuaPlayer The player to create the window for
--- @param player_table PlayerData The player's data table
function main_window.create(player, player_table)
  -- If window already exists, destroy it first
  main_window.destroy(player, player_table)

  -- Create main window frame
  local window = player.gui.screen.add {
    type = "frame",
    name = WINDOW_NAME,
    direction = "vertical",
    style = "botsgui_frame_style",
    visible = player_table.bots_window_visible and player.controller_type ~= defines.controllers.cutscene,
  }

  -- Create title bar with control buttons
  main_window._add_titlebar(window, player_table)

  -- Create main content table
  local content_table = window.add {
    type = "table",
    name = "bots_table",
    style = "li_mainwindow_content_style",
    column_count = player_table.settings.max_items + 1
  }

  player_table.bots_table = content_table
  -- Add all of the data rows
  main_window._add_all_rows(player_table, content_table)

  -- Restore the previous location, if it exists
  local gui = player.gui.screen
  if gui then
    if player_table.window_location then
      gui.logistics_insights_window.location = player_table.window_location
    else
      gui.logistics_insights_window.location = { x = 200, y = 0 }
    end
  end
end

--- Make sure all the relevant parts of the UI are available and initialised
--- @param player LuaPlayer The player whose UI to ensure consistency for
--- @param player_table PlayerData The player's data table
function main_window.ensure_ui_consistency(player, player_table)
  local gui = player.gui.screen
  if not gui.logistics_insights_window or not player_table.ui then
    main_window.create(player, player_table)
  end

  local window = gui.logistics_insights_window

  if game_state.needs_buttons() then
    local titlebar = window["logistics-insights-title-bar"]
    if titlebar then
      local unfreeze = titlebar["logistics-insights-unfreeze"]
      local freeze = titlebar["logistics-insights-freeze"]
      game_state.init(unfreeze, freeze)
      game_state.force_update_ui()
    end
  end

  -- Make sure the "Fixed network" toggle is set correctly. 
  -- It cannot be un-set in player_data if the fixed network is deleted
  if window and window.bots_table then
    network_id_cell = window.bots_table["logistics-insights-network-id"]
    if network_id_cell then
      network_id_cell.toggled = player_table and player_table.fixed_network or false
    end
  end
end

--- Add the titlebar to the window with game control buttons
--- @param window LuaGuiElement The main window frame
--- @param player_table PlayerData The player's data table
function main_window._add_titlebar(window, player_table)
  -- Create title bar flow
  local titlebar = window.add {
    type = "flow",
    name = "logistics-insights-title-bar",
  }
  titlebar.drag_target = window

  -- Add title label
  titlebar.add {
    type = "label",
    caption = {"mod-name.logistics-insights"},
    style = "frame_title",
    ignored_by_interaction = true
  }

  local dragger = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    height = 24,
    right_margin = 4,
    ignored_by_interaction = true
  }
  dragger.style.horizontally_stretchable = true
  dragger.style.vertically_stretchable = true

  local unfreeze = titlebar.add {
    type = "sprite-button",
    sprite = "li_play",
    style = "tool_button",
    name = "logistics-insights-unfreeze",
    tooltip = {"bots-gui.unfreeze-game-tooltip"},
  }
  local freeze = titlebar.add {
    type = "sprite-button",
    sprite = "li_pause",
    style = "tool_button",
    name = "logistics-insights-freeze",
    tooltip = {"bots-gui.freeze-game-tooltip"},
  }
  titlebar.add {
    type = "sprite-button",
    sprite = "li_step",
    style = "tool_button",
   name = "logistics-insights-step",
    tooltip = {"bots-gui.step-game-tooltip"},
  }
  game_state.init(unfreeze, freeze)
  game_state.force_update_ui()
end

--- Add all row types to the content table
--- @param player_table PlayerData The player's data table
--- @param content_table LuaGuiElement The table to add rows to
function main_window._add_all_rows(player_table, content_table)
  -- First clear all existing UI elements
  content_table.clear()

  -- Add all of possible rows: The routines check if they are enabled in settings
  delivery_row.add(player_table, content_table)
  history_rows.add(player_table, content_table)
  activity_row.add(player_table, content_table)
  network_row.add(player_table, content_table)
  undersupply_row.add(player_table, content_table)
  suggestions_row.add(player_table, content_table)
end

--- Update all rows with current data
--- @param player LuaPlayer The player whose window to destroy
--- @param player_table PlayerData The player's data table
--- @param clearing boolean Whether this update is due to clearing history
function main_window.update(player, player_table, clearing)
  if not player_table.ui then
    if player.gui.screen.logistics_insights_window then
      player_table.ui = player.gui.screen.logistics_insights_window
    else
      return -- No UI to update
    end
  end
  -- Update shortcut toggle state to match window visibility
  player.set_shortcut_toggled("logistics-insights-toggle", player_table.bots_window_visible)
  if not player_table.ui or not player_table.bots_window_visible then
    return
  end

  -- Update all of the rows; each row will only update if enabled in settings.
  delivery_row.update(player_table, clearing)
  history_rows.update(player_table, clearing)
  activity_row.update(player_table)
  network_row.update(player_table)
  undersupply_row.update(player_table)
  suggestions_row.update(player_table)
end

-- Update the Delivery progress bar
--- @param player_table PlayerData The player's data table
--- @param progress Progress|nil The progress data with current and total values
function main_window.update_bot_progress(player_table, progress)
  progress_bars.update_progressbar(player_table, "deliveries-row", progress)
end

-- Update the Activity progress bar
--- @param player_table PlayerData The player's data table
--- @param progress Progress|nil The progress data with current and total values
function main_window.update_cells_progress(player_table, progress)
  progress_bars.update_progressbar(player_table, "activity", progress)
end

--- Destroy the main window
--- @param player LuaPlayer The player whose window to destroy
--- @param player_table PlayerData The player's data table
function main_window.destroy(player, player_table)
  if player.valid and player.gui.screen.logistics_insights_window then
    player.gui.screen.logistics_insights_window.destroy()
    if player_table and player_table.bots_table then
      player_table.bots_table = nil
    end
  end

  player_table.ui = {}
end

--- Toggle window visibility
--- @param player LuaPlayer|nil The player whose window to toggle
function main_window.toggle_window_visible(player)
  if not player or not player.valid then
    return
  end
  local player_table = storage.players[player.index]

  -- Toggle the desired state
  player_table.bots_window_visible = not player_table.bots_window_visible

  -- Figure out if the paused state needs changing as a result
  if player_table.history_timer and player_table.settings.pause_while_hidden then
    if not player_table.bots_window_visible then
      -- History collection pauses when the window is minimized, but remember paused state
      player_table.saved_paused_state = player_table.history_timer:is_paused()
      player_table.history_timer:pause()
    else
      -- Restore prior paused state
      player_table.history_timer:set_paused(player_table.saved_paused_state)
    end
  end

  local gui = player.gui.screen
  if not gui.logistics_insights_window then
    main_window.create(player, player_table)
  end
  if gui.logistics_insights_window then
    gui.logistics_insights_window.visible = player_table.bots_window_visible
  end
end

--- Check if the window is currently open
--- @param player_table PlayerData The player's data table
--- @return boolean true if the window is open and valid
function main_window.is_open(player_table)
  if not player_table or not player_table.ui or not player_table.ui.window then
    return false
  end
  return player_table.ui.window and player_table.ui.window.valid
end

--- Handle click events on GUI elements
--- @param event EventData.on_gui_click The click event data
function main_window.onclick(event)
  if utils.starts_with(event.element.name, "logistics-insights") then
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()
    if player and player.valid and player_table then
      local cleared = false
      if event.element.name == "logistics-insights-unfreeze" then
        -- Unfreeze the game after it's been frozen
        find_and_highlight.clear_markers(player)
        game_state.unfreeze_game()
      elseif event.element.name == "logistics-insights-freeze" then
        -- Freeze the game so player can inspect the state
        game_state.freeze_game()
      elseif event.element.name == "logistics-insights-step" then
        -- Single-step the game to see what happens
        game_state.step_game()
      elseif event.element.name == "logistics-insights-network-id" then
        -- Clicking the network ID button toggles between fixed and dynamic network
        event.element.toggled = not event.element.toggled
        player_table.fixed_network = event.element.toggled
      elseif event.element.name == "logistics-insights-sorted-clear" then
        -- Clear the delivery history and clear the timer
        storage.delivery_history = {}
        if player_table and player_table.history_timer then
          player_table.history_timer:reset_keep_pause()
        end
        cleared = true
        main_window.update(player, player_table, true)
      elseif event.element.name == "logistics-insights-sorted-delivery" then
        pause_manager.toggle_paused(player_table.paused_items, "delivery")
      elseif event.element.name == "logistics-insights-sorted-history" then
        pause_manager.toggle_paused(player_table.paused_items, "history")
      elseif event.element.name == "logistics-insights-sorted-activity" then
        pause_manager.toggle_paused(player_table.paused_items, "activity")
      elseif event.element.name == "logistics-insights-sorted-undersupply" then
        pause_manager.toggle_paused(player_table.paused_items, "undersupply")
      elseif event.element.name == "logistics-insights-sorted-suggestions" then
        pause_manager.toggle_paused(player_table.paused_items, "suggestions")
      elseif event.element.tags and player then
        -- Highlight elements. If right-click, also focus on random element
        find_and_highlight.highlight_locations_on_map(player, player_table, event.element, event.button == defines.mouse_button_type.right)
      end

      if utils.starts_with(event.element.name, "logistics-insights-sorted") then
        -- A mini button was clicked, update the UI
        main_window.update(player, player_table, cleared) 
      end
    end
  end
end

-- When the window is moved, remember its new location
script.on_event(defines.events.on_gui_location_changed,
  ---@param event EventData.on_gui_location_changed
  function(event)
  if event.element and event.element.name == WINDOW_NAME then
    local player_table = storage.players[event.player_index]
    if player_table then
      player_table.window_location = event.element.location
    end
  end
end)

return main_window