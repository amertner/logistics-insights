-- Activity row functionality for the logistics insights GUI
-- Handles real-time logistics activity monitoring and display

local activity_row = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local tooltips_helper = require("scripts.tooltips-helper")
local mini_button = require("scripts.mainwin.mini_button")
local progress_bars = require("scripts.mainwin.progress_bars")

-- Cache frequently used functions
local pairs = pairs

--- Add the activity row to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
function activity_row.add(player_table, gui_table)
  local activity_icons = {
    { sprite = "entity/logistic-robot",
      key = "logistic-robot-total",
      tip = "activity-row.robots-total-tooltip",
      clicktip = true,
      onwithpause = true,
      include_construction = false},
    { sprite = "virtual-signal/signal-battery-full",
      key = "logistic-robot-available",
      tip = "activity-row.robots-available-tooltip",
      qualitytable = "idle_bot_qualities",
      clicktip = false,
      onwithpause = false,
      include_construction = false },
    { sprite = "virtual-signal/signal-battery-mid-level",
      key = "charging-robot",
      tip = "activity-row.robots-charging-tooltip",
      qualitytable = "charging_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = true },
    { sprite = "virtual-signal/signal-battery-low",
      key = "waiting-for-charge-robot",
      tip = "activity-row.robots-waiting-tooltip",
      qualitytable = "waiting_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = true },
    { sprite = "virtual-signal/signal-input",
      key = "picking",
      tip = "activity-row.robots-picking_up-tooltip",
      qualitytable = "picking_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = false },
    { sprite = "virtual-signal/signal-output",
      key = "delivering",
      tip = "activity-row.robots-delivering-tooltip",
      qualitytable = "delivering_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = false },
  }

  if not player_table.settings.show_activity then
    return 0
  end
  player_data.register_ui(player_table, "activity")
  local cell = gui_table.add {
    name = "bots_activity_row",
    type = "flow",
    direction = "vertical",
    style = "li_row_vflow"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal",
    style= "li_row_hflow"
  }
  hcell.style.horizontally_stretchable = true
  hcell.add {
    type = "label",
    caption = {"activity-row.header"},
    style = "li_row_label",
    tooltip = {"activity-row.header-tooltip"},
  }

  progress_bars.add_progress_indicator(player_table, cell, "activity")

  player_table.ui.activity.cells = {}
  for i, icon in ipairs(activity_icons) do
    local cellname = "logistics-insights-" .. icon.key
    player_table.ui.activity.cells[icon.key] = {
      tip = icon.tip,
      onwithpause = icon.onwithpause,
      clicktip = icon.clicktip,
      qualitytable = icon.qualitytable,
      include_construction = icon.include_construction,
      cell = gui_table.add {
        type = "sprite-button",
        sprite = icon.sprite,
        style = "slot_button",
        name = cellname,
        tags = { follow = true }
      },
    }
  end

  -- Pad with blank elements if needed
  local count = #activity_icons
  while count < player_table.settings.max_items do
    gui_table.add {
      type = "empty-widget",
    }
    count = count + 1
  end
  return 1
end

--- Check if deliveries should be shown based on settings
--- @param player_table PlayerData The player's data table
--- @return boolean True if deliveries should be shown
function activity_row.should_show_deliveries(player_table)
  -- Show deliveries if the setting is enabled or if history is shown
  return player_table.settings.show_delivering or player_table.settings.show_history
end

--- Update the bot activity row with current statistics
--- @param player_table PlayerData The player's data table
function activity_row.update(player_table)
  --- Reset all cells in the ui_table to empty state
  --- @param ui_table table The UI table containing cells to reset
  --- @param sprite boolean Whether to reset sprite property
  --- @param number boolean Whether to reset number property
  --- @param tip boolean Whether to reset tooltip property
  --- @param disable boolean Whether to disable the cells
  local reset_activity_buttons = function(ui_table, sprite, number, tip, disable)
    -- Reset all cells in the ui_table to empty
    for _, cell in pairs(ui_table) do
      if cell and cell.cell and cell.cell.valid and cell.cell.type == "sprite-button" then
        cell = cell.cell -- Get the actual sprite-button
        if sprite then cell.sprite = "" end
        if tip then cell.tooltip = "" end
        if number then cell.number = nil end
        if disable then cell.enabled = false end
      end
    end
  end

  --- Get the appropriate robot format string based on construction inclusion
  --- @param window table The window data containing include_construction flag
  --- @return string The localization key for robot format string
  local function get_robot_formatstr(window)
    if window.include_construction then
      return "bots-gui.format-all-robots"
    else
      return "bots-gui.format-logistics-robots"
    end
  end

  if not player_table.settings.show_activity then
    return
  end

  local networkdata = network_data.get_networkdata(player_table.network)
  if player_table.network and networkdata then
    for key, window in pairs(player_table.ui.activity.cells) do
      if window.cell.valid then
        local num = networkdata.bot_items[key] or 0
        window.cell.number = num

        -- "N <robot-icons> in network doing <activity>"
        local main_tip = {"", {window.tip, {get_robot_formatstr(window), num}}}
        local qualities_table = window.qualitytable
        if qualities_table then
          --  Augment the tooltip with a list of qualities found, if enabled in settings
          local qualities_tooltip = tooltips_helper.get_quality_tooltip_line({""}, networkdata[qualities_table])
          main_tip = {"", main_tip, "\n", qualities_tooltip}
        end

        if window.clicktip then
          -- Only show the "what happens if you click" tooltip if the button is active
          if window.onwithpause or not player_table.settings.pause_for_bots then
            window.cell.tooltip = {"", main_tip, "\n", {"bots-gui.show-location-tooltip"}}
          else
            window.cell.tooltip = {"", main_tip, "\n", {"bots-gui.show-location-and-pause-tooltip"}}
          end
        else
          window.cell.tooltip = main_tip
        end
        window.cell.enabled = true
      end
    end
  else -- No network, reset all activity buttons
    if player_table.ui.activity and player_table.ui.activity.cells then
      reset_activity_buttons(player_table.ui.activity.cells, false, true, true, false)
    end
  end
end -- update

return activity_row