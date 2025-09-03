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
  local lprogress = parent.add {
      type = "label",
      caption = nil,
      style = "li_progress_label",
      tooltip = {"bots-gui.progress-tooltip"}
    }
  if not player_table.ui[progressbar_name] then
    player_table.ui[progressbar_name] = {}
  end
  player_table.ui[progressbar_name].progress_label = lprogress
end

--- Update a progress bar with current progress information
--- @param player_table PlayerData The player's data table
--- @param progressbar_name string The name of the UI element that has a progressbar
--- @param progress Progress|nil The progress data with current and total values
function progress_bars.update_progressbar(player_table, progressbar_name, progress)
  if not player_table.ui or not player_table.ui[progressbar_name] then
    return
  end
  local progress_label = player_table.ui[progressbar_name].progress_label
  if progress_label and progress_label.valid then
    progress_label.caption = {"bots-gui.progress-label_1count_2total", (progress and progress.current - 1) or 0, (progress and progress.total) or 0}
    return
  end
end

return progress_bars
