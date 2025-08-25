--- Manage the state of mini buttons that are added to individual rows in the main window

local mini_button = {}
local player_data = require("scripts.player-data")

---@alias ButtonType "pause" | "trash" | "networks"

--- Update the start/stop button appearance based on current state
--- @param element LuaGuiElement The button element to update
--- @param is_paused boolean Whether the data gathering is currently paused
function mini_button.update_paused(element, is_paused)
  -- Update button appearance to reflect current state
  if element then
    if is_paused then
      element.sprite = "li_play"
    else
      element.sprite = "li_pause"
    end
  end
end

--- @param player_table PlayerData The player's data table
---@param name string The name of the button
local function get_button(player_table, name)
  if player_table and player_table.ui then
    local button = player_table.ui[name .. "_control"]
    if button and button.valid then
      return button
    end
  end
  return nil
end

--- Update the paused state of a mini button by name
--- @param player_table PlayerData The player's data table
---@param name string The name of the button to update
---@param is_paused boolean Whether the button should show as paused
function mini_button.update_paused_state(player_table, name, is_paused)
  local button = get_button(player_table, name)
  if button then
    mini_button.update_paused(button, is_paused)
  end
end

--- Enable/disable a mini button by name
--- @param player_table PlayerData The player's data table
---@param name string The name of the button to update
function mini_button.set_enabled(player_table, name, enabled)
  local button = get_button(player_table, name)
  if button then
    button.enabled = enabled
  end
end

-- Add a button to control the pause state of the row
---@param player_table PlayerData The player's data table
---@param label_ui LuaGuiElement The parent UI element to add the button to
---@param button_name string The button identifier ("history", "undersupply", etc.)
---@param tooltip LocalisedString The tooltip identifier for the button
---@param button_type ButtonType The type of button ("pause", "trash", etc.)
---@param is_paused boolean Whether the button should start in a paused state
function mini_button.add(player_table, label_ui, button_name, tooltip, button_type, is_paused)
  -- Add flexible spacer that pushes button to the right
  local space = label_ui.add {
    type = "empty-widget",
    style = "draggable_space",
  }
  space.style.horizontally_stretchable = true

  -- Determine the sprite based on button type
  local sprite
  if button_type == "pause" then
    if is_paused then
      sprite = "li_play"
    else
      sprite = "li_pause"
    end
  elseif button_type == "trash" then
    sprite = "utility/trash"
  elseif button_type == "networks" then
    sprite = "virtual-signal/signal-stack-size" -- Looks a bit like a list of stuff
  end

  -- Add right-aligned button that's vertically centered with the label
  local row_button = label_ui.add {
    type = "sprite-button",
    style = "mini_button", -- Small button size
    sprite = sprite,
    name = "logistics-insights-sorted-" .. button_name,
    tooltip = tooltip
  }

  -- Make button vertically centered with a small top margin for alignment
  row_button.style.top_margin = 2
  label_ui.style.vertical_align = "center"

  -- Register pause buttons in the player's UI table
  if player_table.ui and button_type == "pause" then
    player_table.ui[button_name .. "_control"] = row_button
  end

  return row_button
end

return mini_button