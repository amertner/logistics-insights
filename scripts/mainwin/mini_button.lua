--- Manage the state of mini buttons that are added to individual rows in the main window

local mini_button = {}

---@alias ButtonType "trash" | "networks" | "settings"

-- Add a small button at the right-hand end of a row's label
---@param player_table PlayerData The player's data table
---@param label_ui LuaGuiElement The parent UI element to add the button to
---@param button_name string The button identifier ("history", "undersupply", etc.)
---@param tooltip LocalisedString The tooltip identifier for the button
---@param button_type ButtonType The type of button ("trash", etc.)
function mini_button.add(player_table, label_ui, button_name, tooltip, button_type)
  -- Add flexible spacer that pushes button to the right
  local space = label_ui.add {
    type = "empty-widget",
    style = "draggable_space",
  }
  space.style.horizontally_stretchable = true

  -- Determine the sprite based on button type
  local sprite
  if button_type == "trash" then
    sprite = "utility/trash"
  elseif button_type == "networks" then
    sprite = "li_list"
  elseif button_type == "settings" then
    sprite = "li-settings"
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

  return row_button
end

return mini_button