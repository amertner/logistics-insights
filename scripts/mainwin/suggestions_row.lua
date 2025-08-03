--- Shows suggestions for how the Logistics Network could work better

local player_data = require("scripts.player-data")
local suggestions = require("scripts.suggestions")

local suggestions_row = {}
local ROW_TITLE = "suggestions-row"

-- Import status codes for easier reference
local SuggestionsStatusCodes = suggestions.StatusCodes

---@param player_table PlayerData The player's data table
---@param gui_table LuaGuiElement The GUI table to add the row to
function suggestions_row.add(player_table, gui_table)
  if not player_table.settings.show_suggestions then
    return
  end
  player_data.register_ui(player_table, ROW_TITLE)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical",
    vertically_squashable = false,
    minimal_height = 80, -- Need to have room for a slot button
  }
  cell.style.vertically_stretchable = false
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal",
    vertically_squashable = false,
    minimal_height = 80, -- Need to have room for a slot button
  }
  hcell.style.horizontally_stretchable = true

  -- Add left-aligned label
  local titlecell = hcell.add {
    type = "label",
    name = ROW_TITLE .. "-title",
    caption = {ROW_TITLE .. ".header"},
    style = "heading_2_label",
    tooltip = {"", {ROW_TITLE .. ".header-tooltip"}}
  }

  -- Remember the title cell so we can update the tooltip later
  player_table.ui[ROW_TITLE].titlecell = titlecell
  player_table.ui[ROW_TITLE].suggestion_buttons = {}
  for count = 1, player_table.settings.max_items do
    -- Add an empty widget for when there is no suggestion
    -- Add sprite button (hidden by default)
    player_table.ui[ROW_TITLE].suggestion_buttons[count] = gui_table.add {
      type = "sprite-button",
      sprite = "li_arrow",
      style = "slot_button",
      show_percent_for_small_numbers = true,
      visible = false
    }  
  end
end

---@param items LuaGuiElement The parent of cells and suggestion_buttons
---@index number The index of the cell to update
---@param suggestion? Suggestion The suggestion object containing details, or nil to clear
function suggestions_row.set_suggestion_cell(items, index, suggestion)
  if items.suggestion_buttons == nil then
    return -- No buttons to update
  end
  local button = items.suggestion_buttons[index]
  if button and button.valid then
    if suggestion then
      button.sprite = suggestion.sprite or "li_arrow"
      button.tooltip = suggestion.action or ""
      button.number = suggestion.count or nil
      button.visible = true
      if suggestion.urgency == "high" then
        button.style = "red_slot_button"
      else
        button.style = "yellow_slot_button"
      end
    else
      button.visible = false
    end
  end
end

---@param player_table PlayerData The player's data table
---@return number The number of suggestions shown
function suggestions_row.show_suggestions(player_table)
  local suggestions_table = player_table.suggestions:get_suggestions()
  local items = player_table.ui[ROW_TITLE]

  index = 1
  for name, suggestion in pairs(suggestions_table) do
    suggestions_row.set_suggestion_cell(items, index, suggestion)
    index = index + 1
  end
  return index-1
end

---@param player_table PlayerData The player's data table
function suggestions_row.update(player_table)
  -- If suggestions are not enabled, do nothing
  if not player_table or not player_table.settings.show_suggestions then
    return
  end
  -- If the UI is not available, do nothing
  if not player_table.ui or not player_table.ui[ROW_TITLE] or not player_table.ui[ROW_TITLE].titlecell then
    return
  end
  if not player_table.suggestions or not player_table.suggestions._historydata then
    player_table.suggestions = suggestions.new() -- TODO: Just return on release
  end

  -- Show all suggestions
  index = suggestions_row.show_suggestions(player_table)
  -- Clear any remaining cells
  local items = player_table.ui[ROW_TITLE]
  for i = index+1, player_table.settings.max_items do
    suggestions_row.set_suggestion_cell(items, i, nil)
  end
end

return suggestions_row