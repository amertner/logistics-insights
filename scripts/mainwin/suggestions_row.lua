--- Shows suggestions for how the Logistics Network could work better

local player_data = require("scripts.player-data")
local suggestions = require("scripts.suggestions")
local mini_button = require("scripts.mainwin.mini_button")
local network_data = require("scripts.network-data")
local progress_bars = require("scripts.mainwin.progress_bars")

local suggestions_row = {}
local ROW_TITLE = "suggestions-row"

---@param player_table PlayerData The player's data table
---@param gui_table LuaGuiElement The GUI table to add the row to
function suggestions_row.add(player_table, gui_table)
  if not player_table.settings.show_suggestions then
    return 0
  end
  player_data.register_ui(player_table, ROW_TITLE)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical",
    vertically_squashable = false,
    style = "li_row_vflow"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal",
    vertically_squashable = false,
    style="li_row_hflow"
  }
  hcell.style.horizontally_stretchable = true

  -- Add left-aligned label
  local titlecell = hcell.add {
    type = "label",
    name = ROW_TITLE .. "-title",
    caption = {ROW_TITLE .. ".header"},
    style = "li_row_label",
    tooltip = {"", {ROW_TITLE .. ".header-tooltip"}}
  }

  progress_bars.add_progress_indicator(player_table, cell, "suggestions-row")

  -- Remember the title cell so we can update the tooltip later
  player_table.ui[ROW_TITLE].titlecell = titlecell
  player_table.ui[ROW_TITLE].suggestion_buttons = {}

  -- Placeholder button (always reserves height). Hidden when real suggestions exist.
  player_table.ui[ROW_TITLE].placeholder_button = gui_table.add {
    type = "sprite-button",
    name = "logistics-insights-suggestion/placeholder",
    sprite = "virtual-signal/signal-hourglass",
    style = "slot_button",
    enabled = false,
    tooltip = {"", {ROW_TITLE .. ".no-suggestions"}},
    visible = true
  }

  for count = 1, player_table.settings.max_items do
    -- Add an empty widget for when there is no suggestion
    -- Add sprite button (hidden by default)
    player_table.ui[ROW_TITLE].suggestion_buttons[count] = gui_table.add {
      type = "sprite-button",
      sprite = "li_arrow",
      style = "slot_button",
      name = "logistics-insights-suggestion/" .. count,
      show_percent_for_small_numbers = true,
      visible = false
    }
  end
  return 1
end

---@param items LuaGuiElement The parent of cells and suggestion_buttons
---@index number The index of the cell to update
---@param suggestion? Suggestion The suggestion object containing details, or nil to clear
---@param enabled boolean Whether the button should be enabled
function suggestions_row.set_suggestion_cell(items, index, suggestion, enabled)
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
      button.enabled = enabled
      if suggestion.clickname then
        -- This is a clickable suggestion, so update the tooltip
        button.tags = {clickname = suggestion.clickname}
        button.tooltip = {"", button.tooltip, "\n", {"suggestions-row." .. suggestion.clickname .. "-tooltip"}}
      else
        button.tags = {} -- Clear tags if not clickable
      end
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
---@param suggestions_table Suggestions The suggestions list to show
---@param enabled boolean Whether suggestions are enabled
---@return number The number of suggestions shown
function suggestions_row.show_suggestions(player_table, suggestions_table, enabled)
  local items = player_table.ui[ROW_TITLE]

  local order = (suggestions_table and suggestions_table.order) or (suggestions_table.order) or {}
  local suggestions_list = suggestions_table:get_suggestions()
  local max_items = player_table.settings.max_items
  local index = 1
  -- Pass 1: high urgency in order
  for _, key in ipairs(order) do
    if index > max_items then break end
    local s = suggestions_list[key]
    if s and s.urgency == "high" then
      suggestions_row.set_suggestion_cell(items, index, s, enabled)
      index = index + 1
    end
  end
  -- Pass 2: remaining (low or not high) in order
  if index <= max_items then
    for _, key in ipairs(order) do
      if index > max_items then break end
      local s = suggestions_list[key]
      if s and s.urgency ~= "high" then
        suggestions_row.set_suggestion_cell(items, index, s, enabled)
        index = index + 1
      end
    end
  end
  local shown = index - 1
  -- Toggle placeholder visibility
  local placeholder = items.placeholder_button
  if placeholder and placeholder.valid then
    placeholder.visible = (shown == 0)
    if enabled then
      placeholder.tooltip = {"", {ROW_TITLE .. ".no-suggestions"}}
    else
      placeholder.tooltip = {"", {ROW_TITLE .. ".suggestions-paused"}}
    end
  end
  return shown
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
  local networkdata = network_data.get_networkdata(player_table.network)
  local shown = 0
  local running = false
  if networkdata and networkdata.suggestions and networkdata.suggestions._historydata then
    -- Show all suggestions
    shown = suggestions_row.show_suggestions(player_table, networkdata.suggestions, true)
  end
  -- Clear any remaining cells
  local items = player_table.ui[ROW_TITLE]
  for i = shown + 1, player_table.settings.max_items do
    suggestions_row.set_suggestion_cell(items, i, nil, running)
  end
end

return suggestions_row