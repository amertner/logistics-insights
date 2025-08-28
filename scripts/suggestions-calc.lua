--- Code to calculate suggestions for networks
local suggestions_calc = {}

local SuggestionsMgr = require("scripts.suggestions")
local capability_manager = require("scripts.capability-manager")
local undersupply = require("scripts.undersupply")
local network_data = require("scripts.network-data")

local BOT_TREND_WINDOW_TICKS = 60 * 10 -- 10 seconds window for trend
local MIN_TOTAL_BOTS_FOR_SUGGESTION = 100 -- Ignore small networks

-- Scheduler-driven evaluation helpers (dirty-flag + interval externalised)
--- Evaluate cell-related suggestions if needed (scheduler sets dirty flag and cadence)
--- @param suggestions Suggestions The suggestions manager
--- @param player_table PlayerData
--- @param waiting_to_charge_count number The number of bots waiting to charge
--- @return boolean True if something was evaluated, false if skipped due to not dirty
function suggestions_calc.evaluate_player_cells(suggestions, player_table, waiting_to_charge_count)
  if not player_table then return false end
  -- Consume dirty flag from capability manager; if not dirty skip
  if not capability_manager.consume_dirty(player_table, "suggestions") then return false end

  suggestions:update_tick()
  local network = player_table.network
  suggestions_calc.analyse_waiting_to_charge(suggestions, waiting_to_charge_count)
  suggestions_calc.analyse_storage(suggestions, network)
  return true
end

-- Scheduler-driven evaluation helpers (dirty-flag + interval externalised)
--- Evaluate cell-related suggestions if needed (scheduler sets dirty flag and cadence)
--- @param suggestions Suggestions The suggestions manager
--- @param network LuaLogisticNetwork The network to evaluate
--- @param waiting_to_charge_count number The number of bots waiting to charge
function suggestions_calc.evaluate_background_cells(suggestions, network, waiting_to_charge_count)
  suggestions_calc.analyse_waiting_to_charge(suggestions, waiting_to_charge_count)
  suggestions_calc.analyse_storage(suggestions, network)
end

--- Evaluate bot-related suggestions & undersupply if needed
--- @param suggestions Suggestions The suggestions manager
--- @param player_table PlayerData
--- @return boolean True if something was evaluated, false if skipped due to not dirty
function suggestions_calc.evaluate_player_bots(suggestions, player_table)
  if not player_table then return false end
  if not capability_manager.consume_dirty(player_table, "suggestions") then return false end

  suggestions:update_tick()
  local network = player_table.network
  if network then
    suggestions_calc.analyse_too_many_bots(suggestions, network)
    return true
  end
  return false
end

--- Evaluate bot-related suggestions & undersupply if needed
--- @param suggestions Suggestions The suggestions manager
--- @param network LuaLogisticNetwork The network to evaluate
function suggestions_calc.evaluate_background_bots(suggestions, network)
  suggestions:update_tick()
  suggestions_calc.analyse_too_many_bots(suggestions, network)
end

--- Evaluate undersupply based on latest bot data without consuming dirty flag (runs even if suggestions paused)
--- @param networkdata LINetworkData The network data associated with this processing
--- @param player_table PlayerData
--- @param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
--- @param consume_flag boolean Whether to consume the dirty flag (default: false)
--- @return Progress Data for progress indicator
function suggestions_calc.evaluate_player_undersupply(networkdata, player_table, bot_deliveries, consume_flag)
  local progress = { current = 0, total = 0 } -- Use local variable to avoid global access
  if not player_table then
    return progress -- Ignore if no player_table is provided
  end

  local network = player_table.network
  if not network then
    return progress -- Ignore if no player_table is provided
  end

  if networkdata.undersupply_chunker:is_done() then
    -- Pass was completed, so store results
    networkdata.suggestions:set_cached_list("undersupply", networkdata.undersupply_chunker:get_partial_data().net_demand)
    networkdata.suggestions:update_tick()

    -- Only proceed to start a new run if undersupply capability is dirty
    local dirty = capability_manager.consume_dirty(player_table, "undersupply")
    if not dirty then
      return progress
    end
    -- Prior pass was done, so start a new pass
    networkdata.undersupply_chunker:initialise_chunking(networkdata, network.requesters, bot_deliveries, {}, undersupply.initialise_undersupply)
  end
  networkdata.undersupply_chunker:process_chunk(undersupply.process_one_requester, undersupply.all_chunks_done)

  return networkdata.undersupply_chunker:get_progress()
end

--- Evaluate undersupply for a background network
--- @param suggestions Suggestions The suggestions manager
--- @param network LuaLogisticNetwork The network to evaluate
--- @param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
function suggestions_calc.evaluate_background_undersupply(suggestions, network, bot_deliveries)
  local excessivedemand = undersupply.analyse_demand_and_supply(network, bot_deliveries)
  suggestions:set_cached_list("undersupply", excessivedemand)
  suggestions:update_tick()
end

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

-- Potential issue #1: Storage chests contain items that do not match the filter
-- Potential issue #2: There is not enough free unfiltered storage space
-- Potential issue #3: Storage chests overall are full, or not enough storage
--- @param suggestions Suggestions The suggestions manager
--- @param network? LuaLogisticNetwork The network being analysed
function suggestions_calc.analyse_storage(suggestions, network)
  if network and network.storages then
    -- Maintain a list of mismatched storages
    local mismatched = {}
    -- Maintain a count of total and free stacks
    local all_stacks, free_stacks = 0, 0
    local unfiltered_stacks, unfiltered_free_stacks = 0, 0
    for _, nstorage in pairs(network.storages) do
      if nstorage.valid then
        local inventory = nstorage.get_inventory(defines.inventory.chest)
        -- Count total and free stacks
        if inventory then
          local capacity = #inventory
          local free = inventory.count_empty_stacks()
          all_stacks = all_stacks + capacity
          free_stacks = free_stacks + free

          -- Iterate over filtered to find mismatches
          if nstorage.filter_slot_count then
            for finx = 1, nstorage.filter_slot_count do
              -- Check if the filter matches the contents
              local filter = nstorage.get_filter(finx)
              if not filter then
                -- There is no filter, count unfiltered capacity
                if finx == 1 then -- If there are multiple filters, only count capacity once
                  unfiltered_stacks = unfiltered_stacks + capacity
                  unfiltered_free_stacks = unfiltered_free_stacks + free
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
                        table.insert(mismatched, nstorage)
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

    -- Create storage capacity suggestions, if the numbers warrant it
    suggestions_calc.create_storage_capacity_suggestion(suggestions, SuggestionsMgr.storage_low_key, all_stacks, free_stacks)
    suggestions_calc.create_storage_capacity_suggestion(suggestions, SuggestionsMgr.unfiltered_storage_low_key, unfiltered_stacks, unfiltered_free_stacks)

    -- Create Mismatched Storage suggestion
    local mismatched_count = #mismatched
    suggestions:create_or_clear_suggestion(SuggestionsMgr.mismatched_storage_key, mismatched_count, "entity/storage-chest", "low", true,
      {"suggestions-row.mismatched-storage-action", mismatched_count})
    suggestions:set_cached_list(SuggestionsMgr.mismatched_storage_key, mismatched) -- Store the list of mismatched storages
  else
    suggestions:clear_suggestion(SuggestionsMgr.mismatched_storage_key)
    suggestions:clear_suggestion(SuggestionsMgr.unfiltered_storage_low_key)
    suggestions:clear_suggestion(SuggestionsMgr.storage_low_key)
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
  local window_start = self._current_tick - BOT_TREND_WINDOW_TICKS
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

return suggestions_calc
