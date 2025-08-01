--- Functionality to help with progress bars

local progress_bars = {}

local player_data = require("scripts.player-data")

-- Cache frequently used constants
local math_floor = math.floor

-- Caching frequently accessed values for progress bars
local cached_chunk_size = 0
local cached_tooltip_complete = nil
local cached_tooltip_data = {}

--- Update cached chunk size value when settings change
function progress_bars.update_chunk_size_cache()
  local new_chunk_size = player_data.get_singleplayer_table().settings.chunk_size or 400

  -- Only invalidate caches if the value actually changed
  if new_chunk_size ~= cached_chunk_size then
    cached_chunk_size = new_chunk_size
    cached_tooltip_complete = nil
    cached_tooltip_data = {}
  end
end

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

  -- Initialize the cache if it's not set yet
  if cached_chunk_size == 0 then
    progress_bars.update_chunk_size_cache()
  end

  if not progress or progress.total == 0 then
    -- Create tooltip only once for the "complete" state
    if not cached_tooltip_complete then
      cached_tooltip_complete = {"bots-gui.chunk-size-tooltip", cached_chunk_size}
    end

    -- Only update if needed (value might already be 1)
    if progressbar.value ~= 1 then
      progressbar.value = 1
    end

    progressbar.tooltip = cached_tooltip_complete
  else
    -- Calculate the new value
    local new_value = progress.current / progress.total

    if math.abs(progressbar.value - new_value) > 0.01 then
      progressbar.value = new_value

      local current_minus_one = progress.current - 1
      local percentage = math_floor((current_minus_one / progress.total) * 100 + 0.5)

      local cache_key = current_minus_one .. "_" .. progress.total
      if not cached_tooltip_data[cache_key] then
        if table_size(cached_tooltip_data) > 500 then
          cached_tooltip_data = {}
        end
        cached_tooltip_data[cache_key] = {"bots-gui.chunk-processed-tooltip-1chunksize-2processed-3total-4percent", cached_chunk_size, current_minus_one, progress.total, percentage}
      end

      progressbar.tooltip = cached_tooltip_data[cache_key]
    end
  end
end

return progress_bars
