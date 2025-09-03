--- Code to calculate suggestions for networks
local suggestions_calc = {}

local SuggestionsMgr = require("scripts.suggestions")
local undersupply = require("scripts.undersupply")
local network_data = require("scripts.network-data")

local BOT_TREND_WINDOW_TICKS = 60 * 10 -- 10 seconds window for trend
local MIN_TOTAL_BOTS_FOR_SUGGESTION = 100 -- Ignore small networks for suggesting too many bots

-- Potential issue: Too many bots waiting to charge means we need more RPs
---@param suggestions Suggestions
---@param waiting_for_charge_count number The number of bots waiting to charge
function suggestions_calc.analyse_waiting_to_charge(suggestions, waiting_for_charge_count)
  local need_rps = (waiting_for_charge_count > 9) and math.ceil(waiting_for_charge_count / 4) or 0
  -- Record the last few numbers so the recommendation does not jump around randomly
  suggestions:remember(suggestions.awaiting_charge_key, need_rps)

  local suggested_number = suggestions:max_from_history(SuggestionsMgr.awaiting_charge_key)
  suggestions:create_or_clear_suggestion(
    SuggestionsMgr.awaiting_charge_key,
    suggested_number,
    "entity/roboport",
    suggestions:get_urgency(suggested_number, 100),
    false,
    {"suggestions-row.waiting-to-charge-action", suggested_number}
  )
end

--- Create a suggestion, if the numbers warrant it
--- @param suggestions Suggestions The suggestions manager
--- @param suggestion_name string The name of the suggestion to create
--- @param total_stacks number The total number of stacks available
--- @param free_stacks number The number of free stacks available
function suggestions_calc.create_storage_capacity_suggestion(suggestions, suggestion_name, total_stacks, free_stacks)
  local used_capacity = 1 -- No stacks = no capacity
  if total_stacks > 0 then used_capacity = 1 - free_stacks / total_stacks end
  local urgency = suggestions:get_urgency(used_capacity, 0.9)
  local used_rounded = math.floor(used_capacity * 1000)/10
  if used_capacity > 0.7 then
    suggestions:create_or_clear_suggestion(suggestion_name, used_rounded, "entity/storage-chest", urgency, false,
      {"suggestions-row." .. suggestion_name .. "-action", used_rounded})
  else
    suggestions:clear_suggestion(suggestion_name)
  end
end

---@class StorageAccumulator
---@field total_stacks number Total number of stacks in all storage chests
---@field free_stacks number Total number of free stacks in all storage chests
---@field unfiltered_total_stacks number Total number of stacks in unfiltered storage chests
---@field unfiltered_free_stacks number Total number of free stacks in unfiltered storage chests
---@field mismatched_storages LuaEntity[] List of storage chests that have items not

-- Get ready to analyse storage in chunks
--- @param accumulator StorageAccumulator The accumulator to store results in
function suggestions_calc.initialise_storage_analysis(accumulator, context)
  accumulator.total_stacks = 0
  accumulator.free_stacks = 0
  accumulator.unfiltered_total_stacks = 0
  accumulator.unfiltered_free_stacks = 0
  accumulator.mismatched_storages = {}
end

--- Process a storage chest for chunked storage analysis
--- @param nstorage LuaEntity The storage chest entity
--- @param accumulator StorageAccumulator The accumulator to store results in
function suggestions_calc.process_storage_for_analysis(nstorage, accumulator)
  if nstorage and nstorage.valid then
    local inventory = nstorage.get_inventory(defines.inventory.chest)
    -- Count total and free stacks
    if inventory then
      local capacity = #inventory
      local free = inventory.count_empty_stacks()
      accumulator.total_stacks = accumulator.total_stacks + capacity
      accumulator.free_stacks = accumulator.free_stacks + free

      -- Iterate over filtered to find mismatches
      if nstorage.filter_slot_count then
        for finx = 1, nstorage.filter_slot_count do
          -- Check if the filter matches the contents
          local filter = nstorage.get_filter(finx)
          if not filter then
            -- There is no filter, count unfiltered capacity
            if finx == 1 then -- If there are multiple filters, only count capacity once
              accumulator.unfiltered_total_stacks = accumulator.unfiltered_total_stacks + capacity
              accumulator.unfiltered_free_stacks = accumulator.unfiltered_free_stacks + free
            end
          else
            if inventory and not inventory.is_empty() then
              -- Placeholder mismatch logic (unchanged)
              local stacks = inventory.get_contents()
              local index = 1
              while index <= #stacks do
                local stack = stacks[index]
                if stack then
                  if stack.name ~= filter.name.name or stack.quality ~= filter.quality.name then
                    -- There are items that do not match the filter
                    table.insert(accumulator.mismatched_storages, nstorage)
                    -- Don't check the rest of the stacks
                    break
                  end
                end
                index = index + 1
              end
            end
          end
        end
      end
    end
  end
end

--- Called when all chunks have been processed
--- @param accumulator StorageAccumulator The accumulator with gathered statistics
--- @param gather GatherOptions Gathering options
--- @param networkdata LINetworkData The network data associated with this processing
function suggestions_calc.all_storage_chunks_done(accumulator, gather, networkdata)
  if networkdata then
    local suggestions = networkdata.suggestions
    if accumulator then
      -- Create storage capacity suggestions, if the numbers warrant it
      suggestions_calc.create_storage_capacity_suggestion(
        suggestions, SuggestionsMgr.storage_low_key, accumulator.total_stacks, accumulator.total_stacks)
      suggestions_calc.create_storage_capacity_suggestion(
        suggestions, SuggestionsMgr.unfiltered_storage_low_key, accumulator.unfiltered_total_stacks, accumulator.unfiltered_free_stacks)

      -- Create Mismatched Storage suggestion
      local mismatched_count = table_size(accumulator.mismatched_storages)
      suggestions:create_or_clear_suggestion(SuggestionsMgr.mismatched_storage_key, mismatched_count, "entity/storage-chest", "low", true,
        {"suggestions-row.mismatched-storage-action", mismatched_count})
      suggestions:set_cached_list(SuggestionsMgr.mismatched_storage_key, accumulator.mismatched_storages) -- Store the list of mismatched storages
    else
      -- Premature completion: We didn't get the data to figure out if there is anything wrong
      suggestions:clear_suggestion(SuggestionsMgr.mismatched_storage_key)
      suggestions:clear_suggestion(SuggestionsMgr.unfiltered_storage_low_key)
      suggestions:clear_suggestion(SuggestionsMgr.storage_low_key)
    end
  end
end

-- Analyse whether the player is adding too many bots: rising total with many idle
---@param suggestions Suggestions The suggestions manager
---@param network? LuaLogisticNetwork
function suggestions_calc.analyse_too_many_bots(suggestions, network)
  if not network then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end
  local total = network.all_logistic_robots or 0
  if total < MIN_TOTAL_BOTS_FOR_SUGGESTION then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end
  local idle = network.available_logistic_robots or 0

  -- Record total for trend analysis
  suggestions:remember(SuggestionsMgr.too_many_bots_key, total)
  local history = suggestions._historydata[SuggestionsMgr.too_many_bots_key]
  if not history or #history < 3 then
    return -- Need more samples
  end
  local window_start = suggestions._current_tick - BOT_TREND_WINDOW_TICKS
  local first, last
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.tick < window_start then
      -- Drop older entries outside window to keep history lean
      table.remove(history, i)
    else
      last = last or entry.data
      first = entry.data
    end
  end
  if not first or not last or last <= first then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end
  local idle_ratio = (total > 0) and (idle / total) or 0
  if idle_ratio <= 0.5 then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end

  -- If more than 80% of bots are idle, make it an urgent suggestion
  local urgency = suggestions:get_urgency(idle_ratio, 0.8)
  local idle_rounded = math.floor(idle_ratio * 1000)/10
  suggestions:create_or_clear_suggestion(
    SuggestionsMgr.too_many_bots_key,
    idle_rounded,
    "entity/logistic-robot",
    urgency,
    false,
    {"suggestions-row.too-many-bots-action", idle_rounded}
  )
end

-- Analyse the trend of idle bots:
-- - whether the player is adding too many bots: rising total with many idle
-- - whether the player needs more bots: all bots busy for a while
---@param suggestions Suggestions The suggestions manager
---@param network? LuaLogisticNetwork
function suggestions_calc.analyse_too_few_bots(suggestions, network)
  if not network then
    suggestions:clear_suggestion(SuggestionsMgr.too_few_bots_key)
    return
  end
  local total = network.all_logistic_robots or 0
  local idle = network.available_logistic_robots or 0

  -- Record idle for trend analysis
  suggestions:remember(SuggestionsMgr.too_few_bots_key, idle)
  -- Look for highest number of idle bots in the window
  history = suggestions._historydata[SuggestionsMgr.too_few_bots_key]
  if not history or #history < 3 then
    return -- Need more samples
  end
  local window_start = suggestions._current_tick - BOT_TREND_WINDOW_TICKS
  local highest_idle = idle
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.tick < window_start then
      -- Drop older entries outside window to keep history lean
      table.remove(history, i)
    else
      if entry.data > highest_idle then
        highest_idle = entry.data
      end
    end
  end

  local idle_ratio = (total > 0) and (idle / total) or 0
  local highest_idle_ratio = (total > 0) and (highest_idle / total) or 0
  if highest_idle_ratio <= 0.02 and total > 0 then
    -- There are bots and 98%+ of them are busy, suggest getting more
    local busy_rounded = math.floor((1-highest_idle_ratio) * 1000)/10
    suggestions:create_or_clear_suggestion(
      SuggestionsMgr.too_few_bots_key,
      busy_rounded,
      "entity/logistic-robot",
      "low",
      false,
      {"suggestions-row.too-few-bots-action"}
    )
    return
  else
    suggestions:clear_suggestion(SuggestionsMgr.too_few_bots_key)
  end
end

return suggestions_calc
