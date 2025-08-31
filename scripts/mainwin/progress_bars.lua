--- Functionality to help with progress bars

local progress_bars = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")

-- Cache frequently used constants
local math_floor = math.floor

--- Update a progress bar with current progress information
--- @param player_table PlayerData The player's data table
--- @param progressbar_name string The name of the UI element that has a progressbar
--- @param progress Progress|nil The progress data with current and total values
function progress_bars.update_progressbar(player_table, progressbar_name, progress)
  if not player_table.ui or not player_table.ui[progressbar_name] then
    return
  end
  local progressbar = player_table.ui[progressbar_name].progressbar
  if not progressbar or not progressbar.valid then
    return
  end
  -- Get the chunk size used for the specific action, if possible
  local chunker = nil
  local chunk_size
  if storage.analysis_state then
    if progressbar_name == "undersupply-row" then
      chunker = storage.analysis_state.undersupply_chunker
      if chunker then
        chunk_size = chunker.CHUNK_SIZE
      end
    end
  end
  if not chunk_size then
    -- Fallback to the global chunk size setting
    chunk_size = global_data.chunk_size()
  end

  if not progress or progress.total == 0 then
    -- Only update if needed (value might already be 1)
    progressbar.value = 1

    progressbar.tooltip = {"bots-gui.chunk-size-tooltip", chunk_size}
  else
    -- Calculate the new value
    local new_value = progress.current / progress.total
    progressbar.value = new_value

    local current_minus_one = progress.current - 1
    local percentage = math_floor((current_minus_one / progress.total) * 100 + 0.5)

    progressbar.tooltip = {"bots-gui.chunk-processed-tooltip-1chunksize-2processed-3total-4percent", chunk_size, current_minus_one, progress.total, percentage}
  end
end

return progress_bars
