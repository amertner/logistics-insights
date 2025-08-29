-- Main window coordinator for the logistics insights GUI
-- Handles window creation, layout, and coordination between different row types

local main_window = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local utils = require("scripts.utils")
local game_state = require("scripts.game-state")
local capability_manager = require("scripts.capability-manager")
local mini_button = require("scripts.mainwin.mini_button")
local find_and_highlight = require("scripts.mainwin.find_and_highlight")
local progress_bars = require("scripts.mainwin.progress_bars")
local delivery_row = require("scripts.mainwin.delivery_row")
local history_rows = require("scripts.mainwin.history_rows")
local activity_row = require("scripts.mainwin.activity_row")
local network_row = require("scripts.mainwin.network_row")
local undersupply_row = require("scripts.mainwin.undersupply_row")
local suggestions_row = require("scripts.mainwin.suggestions_row")
local networks_window = require("scripts.networkswin.networks_window")

-- Control action dispatch (freeze / unfreeze / step)
-- Control button handling moved to game_state.handle_control_button for centralization

-------------------------------------------------------------------------------
-- Create main window and all rows needed based on settings
-------------------------------------------------------------------------------

local WINDOW_NAME = "logistics_insights_window"
local SHORTCUT_TOGGLE = "logistics-insights-toggle"

-- Enable/disable row mini pause buttons based on capability dependencies
function main_window.refresh_mini_button_enabled_states(player_table)
  local snap = capability_manager.snapshot(player_table)
  if not snap then return end
  for name, rec in pairs(snap) do
    if rec then
      local enabled = true
      for _, dep in ipairs(rec.deps or {}) do
        local dep_rec = snap[dep]
        if not (dep_rec and dep_rec.active) then
          enabled = false
          break
        end
      end
      -- This will be a no-op for capabilities without a corresponding mini button
      mini_button.set_enabled(player_table, name, enabled)
    end
  end
end

--- Create the main Logistics Insights window
--- @param player LuaPlayer The player to create the window for
--- @param player_table PlayerData The player's data table
function main_window.create(player, player_table)
  if not player or not player.valid then return end

  -- If window already exists, destroy it first
  main_window.destroy(player, player_table)

  -- Create main window frame
  local window = player.gui.screen.add {
    type = "frame",
    name = WINDOW_NAME,
    direction = "vertical",
    style = "li_window_style",
    visible = player_table.bots_window_visible and player.controller_type ~= defines.controllers.cutscene,
  }
  -- Store root window separately (do not overwrite ui table)
  player_table.window = window
  if not player_table.ui then 
    player_table.ui = {}
  end

  -- Create title bar with control buttons
  main_window._add_titlebar(window, player_table)

  -- Content: Standard frames, with a table for contents
  local inside_frame = window.add{
    type = "frame",
    name = WINDOW_NAME.."-inside",
    style = "inside_shallow_frame",
    direction = "vertical",
  }
    local subheader_frame = inside_frame.add{
      type = "frame",
      name = WINDOW_NAME.."-subheader",
      style = "subheader_frame",
      direction = "horizontal",
    }
      subheader_frame.style.height = 300 -- This dictates how much there is room for
      -- Create main content table
      local content_table = subheader_frame.add {
        type = "table",
        name = "bots_table",
        style = "li_mainwindow_content_style",
        column_count = player_table.settings.max_items + 1
  }

  -- Add all of the data rows
  main_window._add_all_rows(player_table, content_table)

  -- Ensure mini buttons are enabled/disabled according to capability deps
  main_window.refresh_mini_button_enabled_states(player_table)

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
  if not player or not player.valid or not player_table then
    return -- No player, nothing to ensure
  end
  local gui = player.gui.screen
  if not gui.logistics_insights_window or not player_table.ui then
    main_window.create(player, player_table)
  end

  window = player_table.window

  if window and game_state.needs_buttons(player_table) then
    local titlebar = window["logistics-insights-title-bar"]
    if titlebar then
      local unfreeze = titlebar["logistics-insights-unfreeze"]
      local freeze = titlebar["logistics-insights-freeze"]
      game_state.init(player_table, unfreeze, freeze)
      game_state.force_update_ui(player_table, false, false)
    end
  end

  -- Keep mini-button enables in sync with current capability deps
  -- refresh_mini_button_enables(player_table)

  -- Make sure the "Fixed network" toggle is set correctly. 
  -- It cannot be un-set in player_data if the fixed network is deleted
  if window and window.bots_table then
    local network_id_cell = window.bots_table["logistics-insights-network-id"]
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
  local label = titlebar.add {
    type = "label",
    caption = {"mod-name.logistics-insights"},
    style = "frame_title",
    ignored_by_interaction = true
  }
  label.style.top_margin = -4

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
    sprite = "li_play_white",
    style = "frame_action_button",
    name = "logistics-insights-unfreeze",
    tooltip = {"bots-gui.unfreeze-game-tooltip"},
  }
  local freeze = titlebar.add {
    type = "sprite-button",
    sprite = "li_pause_white",
    style = "frame_action_button",
    name = "logistics-insights-freeze",
    tooltip = {"bots-gui.freeze-game-tooltip"},
  }
  titlebar.add {
    type = "sprite-button",
    sprite = "li_step_white",
    style = "frame_action_button",
    name = "logistics-insights-step",
    tooltip = {"bots-gui.step-game-tooltip"},
  }
  titlebar.add({
      type = "sprite-button",
      style = "frame_action_button",
      sprite = "utility/close",
      tooltip = {"bots-gui.close-window-tooltip"},
      name = "logistics-insights-close",
  })

  game_state.init(player_table, unfreeze, freeze)
  -- Register callback to clear highlight markers whenever the game is unfrozen
  game_state.set_on_unfreeze(function(pt)
    local p = game.get_player(pt.player_index)
    if p and p.valid then
      find_and_highlight.clear_markers(p)
    end
  end)
  game_state.force_update_ui(player_table, false, false)
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
  -- Ensure window reference; do NOT assign window to player_table.ui
  if not player_table.window or not player_table.window.valid then
    if player.gui.screen.logistics_insights_window then
      player_table.window = player.gui.screen.logistics_insights_window
    else
      return -- No window to update
    end
  end
  if not player_table.ui then
    player_table.ui = {}
  end
  -- Update shortcut toggle state to match window visibility
  player.set_shortcut_toggled(SHORTCUT_TOGGLE, player_table.bots_window_visible)
  if not player_table.bots_window_visible then
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

-- Update the Undersupply progress bar
--- @param player_table PlayerData The player's data table
--- @param progress Progress|nil The progress data with current and total values
function main_window.update_undersupply_progress(player_table, progress)
  progress_bars.update_progressbar(player_table, "undersupply-row", progress)
end

-- Update the Undersupply progress bar
--- @param player_table PlayerData The player's data table
--- @param progress Progress|nil The progress data with current and total values
function main_window.update_suggestions_progress(player_table, progress)
  progress_bars.update_progressbar(player_table, "suggestions-row", progress)
end

--- Destroy the main window
--- @param player LuaPlayer The player whose window to destroy
--- @param player_table PlayerData The player's data table
function main_window.destroy(player, player_table)
  if player.valid and player.gui.screen.logistics_insights_window then
    player.gui.screen.logistics_insights_window.destroy()
  end
  player_table.window = nil
  player_table.ui = {} -- Keep as table for future register_ui calls
end

--- Toggle window visibility
--- @param player LuaPlayer The player whose window to toggle
--- @param player_table PlayerData The player's data table
--- @param visible boolean Whether the window should be visible
function main_window.set_window_visible(player, player_table, visible)
  player_table.bots_window_visible = visible

  -- Update shortcut button state
  player.set_shortcut_toggled(SHORTCUT_TOGGLE, player_table.bots_window_visible)

  local gui = player.gui.screen
  if not gui.logistics_insights_window then
    main_window.create(player, player_table)
  end
  if gui.logistics_insights_window then
    gui.logistics_insights_window.visible = player_table.bots_window_visible
  end
end

--- Toggle main window visibility
--- @param player LuaPlayer|nil The player whose window to toggle
function main_window.toggle_window_visible(player)
  if not player or not player.valid then
    return
  end
  local player_table = storage.players[player.index]

  -- Toggle the desired state
  main_window.set_window_visible(player, player_table, not player_table.bots_window_visible)
end

--- Handle click events on GUI elements
--- @param event EventData.on_gui_click The click event data
function main_window.onclick(event)
  if utils.starts_with(event.element.name, "logistics-insights") then
    local player = game.get_player(event.player_index)
    local player_table = player_data.get_player_table(event.player_index)
    if player and player.valid and player_table then
      if game_state.handle_control_button(player_table, event.element) then
        -- Control button handled (freeze/unfreeze/step)
      elseif event.element.name == "logistics-insights-close" then
        -- Close button clicked
        main_window.set_window_visible(player, player_table, false)
      elseif event.element.name == "logistics-insights-network-id" then
        -- Clicking the network ID button toggles between fixed and dynamic network
        event.element.toggled = not event.element.toggled
        player_table.fixed_network = event.element.toggled
      elseif event.element.name == "logistics-insights-sorted-network" then
        -- Show/Hide Networks window
        networks_window.toggle_window_visible(player)
      elseif event.element.name == "logistics-insights-sorted-clear" then
        -- Clear the delivery history and clear the timer
        network_data.clear_delivery_history(player_table.network)
        main_window.update(player, player_table, true)
        -- Also update the mini-button state. This is a workaround in case things get stuck.
        main_window.refresh_mini_button_enabled_states(player_table)
      elseif utils.starts_with(event.element.name, "logistics-insights-sorted-") then
        -- Inline handling for mini pause buttons -> toggles capability "user" reason
        local suffix = event.element.name:sub(string.len("logistics-insights-sorted-") + 1)
        local valid = {
          delivery = true, history = true, activity = true, undersupply = true, suggestions = true
        }
        if valid[suffix] then
          local now_paused = not capability_manager.is_active(player_table, suffix)
          -- Toggle
          capability_manager.set_reason(player_table, suffix, "user", not now_paused)
          -- Special side-effect for history timer: Update paused state
          local networkdata = network_data.get_networkdata(player_table.network)
          if suffix == "history" and networkdata and networkdata.history_timer then
            networkdata.history_timer:set_paused(not now_paused)
          end
          -- Update UI mini-button state and dependent enable
          mini_button.update_paused_state(player_table, suffix, not now_paused)
          -- Enable/disable dependent buttons using capability snapshot
          main_window.refresh_mini_button_enabled_states(player_table)
          -- Now update window
          main_window.update(player, player_table, false)
        end
      else
        -- The click may require a highlight/freeze
        local handled = find_and_highlight.handle_click(
          player,
          player_table,
          event.element,
          event.button == defines.mouse_button_type.right
        )
      end
    end
  end
end

-- When the window is moved, remember its new location
function main_window.gui_location_moved(element, player_table)
  if element.name == WINDOW_NAME and player_table then
    if not player_table.window_location then
      player_table.window_location = {}
    end
    player_table.window_location.x = element.location.x
    player_table.window_location.y = element.location.y
  end
end

-- Handle shortcut button clicks
script.on_event(defines.events.on_lua_shortcut,
  --- @param event EventData.on_lua_shortcut
  function(event)
  if event.prototype_name ~= SHORTCUT_TOGGLE then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  -- Toggle window visibility
  main_window.toggle_window_visible(player)
end)

-- Handle keyboard shortcut for main window
script.on_event("logistics-insights-toggle-gui",
  --- @param event EventData.CustomInputEvent
  function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  -- Toggle window visibility
  main_window.toggle_window_visible(player)
end)

-- Handle keyboard shortcut for Networks window
script.on_event("logistics-insights-toggle-networks-gui",
  --- @param event EventData.CustomInputEvent
  function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  -- Toggle window visibility
  networks_window.toggle_window_visible(player)
end)

return main_window