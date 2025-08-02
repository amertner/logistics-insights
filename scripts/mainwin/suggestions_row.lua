--- Shows suggestions for how the Logistics Network could work better

local player_data = require("scripts.player-data")
local suggestions = require("scripts.suggestions")

local suggestions_row = {}
local ROW_TITLE = "suggestions-row"

-- Import status codes for easier reference
local SuggestionsStatusCodes = suggestions.StatusCodes

function suggestions_row.add(player_table, gui_table)
  local title = ROW_TITLE
  player_data.register_ui(player_table, title)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal"
  }
  hcell.style.horizontally_stretchable = true

  -- Add left-aligned label
  local titlecell = hcell.add {
    type = "label",
    caption = {ROW_TITLE .. ".header"},
    style = "heading_2_label",
    tooltip = {"", {ROW_TITLE .. ".header-tooltip"}}
  }

  -- Add item cells
  player_table.ui[title].titlecell = titlecell
  player_table.ui[title].cells = {}
  for count = 1, player_table.settings.max_items do
    player_table.ui[title].cells[count] = gui_table.add {
      type = "sprite-button",
      style = "slot_button",
      enabled = false,
    }
  end
end

function suggestions_row.set_title_tooltip(player_table, status)
  local title = ROW_TITLE
  local tooltip = {"", {title .. ".header-tooltip"}}

  if status == SuggestionsStatusCodes.Analysing then
    tooltip = {"", {title .. ".header-tooltip-analysing"}}
  elseif status == SuggestionsStatusCodes.NoIssues then
    tooltip = {"", {title .. ".header-tooltip-no-issues"}}
  elseif status == SuggestionsStatusCodes.IssuesFound then
    tooltip = {"", {title .. ".header-tooltip-issues-found"}}
  elseif status == SuggestionsStatusCodes.Disabled then
    tooltip = {"", {title .. ".header-tooltip-disabled"}}
  end

  player_table.ui[title].titlecell.tooltip = tooltip
end

function suggestions_row.update(player_table, all_bots)
  -- If the UI is not available, do nothing
  if not player_table.ui or not player_table.ui[ROW_TITLE] or not player_table.ui[ROW_TITLE].titlecell then
    return
  end
  if not player_data.suggestions then
    player_data.suggestions = suggestions.new()
  end

  local status = player_data.suggestions:get_status(player_table)
  suggestions_row.set_title_tooltip(player_table, status)
  if status == SuggestionsStatusCodes.Undefined then
    return -- No suggestions available yet
  end

  -- If paused, just disable all the fields
  if player_data.is_paused(player_table) then
    for i = 1, player_table.settings.max_items do
      local cell = player_table.ui[ROW_TITLE].cells[i]
      if cell and cell.valid then
        cell.enabled = false
      end
    end
    return
  end
end

return suggestions_row