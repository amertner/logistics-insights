--- Functionality to help with progress indicators

local progress_bars = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")

-- Cache frequently used constants
local math_floor = math.floor

function progress_bars.add_progress_indicator(player_table, parent, progressbar_name)
  if not player_table.ui then
    return
  end
  -- Left-aligned counter label, spacer, "of", spacer, right-aligned total label
  local hflow = parent.add {
    type = "flow",
    direction = "horizontal",
    style= "li_row_hflow"
  }
  hflow.style.top_margin = -6
  local lprogress = hflow.add {
      type = "label",
      caption = nil,
      style = "li_progress_label",
      tooltip = {"bots-gui.progress-tooltip"}
    }
  if not player_table.ui.progress_count then
    player_table.ui.progress_count = {}
  end
  player_table.ui.progress_count[progressbar_name] = lprogress
end

--- Update a progress bar with current progress information
--- @param player_table PlayerData The player's data table
--- @param progressbar_name string The name of the UI element that has a progressbar
--- @param progress Progress|nil The progress data with current and total values
function progress_bars.update_progressbar(player_table, progressbar_name, progress)
  if not player_table.ui or not player_table.ui.progress_count or not progress then
    return
  end
  local lcount = player_table.ui.progress_count[progressbar_name]
  if lcount and lcount.valid then
    local total = math.max(progress.total, 1)
    local percent = math_floor(((progress.current-1) / total) * 100)
    lcount.caption = {"bots-gui.progress-percent", percent}
  end
end

--- Clear a progress bar
--- @param player_table PlayerData The player's data table
function progress_bars.clear_all_progressbars(player_table)
  if not player_table.ui or not player_table.ui.progress_count or not player_table.ui.progress_total then
    return
  end
  local labels = player_table.ui.progress_count
  for _, label in pairs(labels) do
    label.caption = ""
  end
end

return progress_bars
