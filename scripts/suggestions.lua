--- Handles suggestions for improving logistics network

local undersupply = require("scripts.undersupply")
local capability_manager = require("scripts.capability-manager")

--- Urgency levels for suggestions
---@alias SuggestionUrgency "high"|"low"

--- Individual suggestion object
---@class Suggestion
---@field name string The name/title of the suggestion
---@field count number? The number associated with the suggestion, if applicable
---@field sprite string The sprite to represent the suggestion visually
---@field urgency SuggestionUrgency The urgency level of the suggestion
---@field action LocalisedString The action to take based on the suggestion
---@field clickname? string Used to get the right action on click, or nil if no click

--- Table containing a historical datapoint
---@class HistoryDataEntry
---@field tick number The time when the suggestion was made
---@field data number The number at the time

--- Table containing historical data for a suggestion
--- @alias HistoryData table<HistoryDataEntry>?
local MAX_HISTORY_TICKS = 60*5 -- 5 seconds
local BOT_TREND_WINDOW_TICKS = 60 * 10 -- 10 seconds window for trend
local MIN_TOTAL_BOTS_FOR_SUGGESTION = 100 -- Ignore small networks

--- Table containing all suggestions
---@alias SuggestionsTable table<string, Suggestion?>

---@class Suggestions
---@field _current_tick number The game tick when suggestions were last updated
---@field _historydata table<string, HistoryData> Historical data needed to make good suggestions
---@field _suggestions SuggestionsTable Table containing all suggestions
---@field _cached_data table<string, table|nil> Cached data for suggestions to be used in the UI
local Suggestions = {}
Suggestions.__index = Suggestions
script.register_metatable("logistics-insights-Suggestions", Suggestions)

Suggestions.awaiting_charge_key = "waiting-to-charge"
Suggestions.storage_low_key = "insufficient-storage"
Suggestions.unfiltered_storage_low_key = "insufficient-unfiltered-storage"
Suggestions.mismatched_storage_key = "mismatched-storage"
Suggestions.undersupply_key = "supply-shortage"
Suggestions.too_many_bots_key = "too-many-bots"
-- Order of suggestions in the UI: First by priority, then by this order:
Suggestions.order = { 
  Suggestions.awaiting_charge_key,
  Suggestions.storage_low_key,
  Suggestions.unfiltered_storage_low_key,
  Suggestions.mismatched_storage_key,
  Suggestions.too_many_bots_key
}

function Suggestions.new()
  local self = setmetatable({}, Suggestions)
  self._current_tick = 0
  self:clear_suggestions()
  return self
end

---@return number The current number of suggestions
function Suggestions:get_current_count()
  local count = 0
  for _, suggestion in pairs(self._suggestions) do
    if suggestion then
      count = count + 1
    end
  end
  return count
end

--- Retrieve the list of current suggestions
--- @return SuggestionsTable The current suggestions
function Suggestions:get_suggestions()
  return self._suggestions
end

-- Get the list of objects for a specific suggestion so it can be used in the UI
---@param suggestion_name AnyBasic The name of the suggestion to retrieve
---@return table|nil A list of items identified as important to the suggestion
function Suggestions:get_cached_list(suggestion_name)
  return self._cached_data[suggestion_name]
end

function Suggestions:set_cached_list(suggestion_name, list)
  self._cached_data[suggestion_name] = list
end


-- Scheduler-driven evaluation helpers (dirty-flag + interval externalised)
--- Evaluate cell-related suggestions if needed (scheduler sets dirty flag and cadence)
--- @param player_table PlayerData
--- @param waiting_to_charge_count number The number of bots waiting to charge
--- @return boolean True if something was evaluated, false if skipped due to not dirty
function Suggestions:evaluate_player_cells(player_table, waiting_to_charge_count)
  if not player_table then return false end
  -- Consume dirty flag from capability manager; if not dirty skip
  if not capability_manager.consume_dirty(player_table, "suggestions") then return false end

  self._current_tick = game.tick
  local network = player_table.network
  self:analyse_waiting_to_charge(waiting_to_charge_count)
  self:analyse_storage(network)
  return true
end

-- Scheduler-driven evaluation helpers (dirty-flag + interval externalised)
--- Evaluate cell-related suggestions if needed (scheduler sets dirty flag and cadence)
--- @param network LuaLogisticNetwork The network to evaluate
--- @param waiting_to_charge_count number The number of bots waiting to charge
function Suggestions:evaluate_background_cells(network, waiting_to_charge_count)
  self:analyse_waiting_to_charge(waiting_to_charge_count)
  self:analyse_storage(network)
end

--- Evaluate bot-related suggestions & undersupply if needed
--- @param player_table PlayerData
--- @return boolean True if something was evaluated, false if skipped due to not dirty
function Suggestions:evaluate_player_bots(player_table)
  if not player_table then return false end
  if not capability_manager.consume_dirty(player_table, "suggestions") then return false end

  self._current_tick = game.tick
  local network = player_table.network
  if network then
    self:analyse_too_many_bots(network)
    return true
  end
  return false
end

--- Evaluate bot-related suggestions & undersupply if needed
--- @param network LuaLogisticNetwork The network to evaluate
function Suggestions:evaluate_background_bots(network)
  self._current_tick = game.tick
  self:analyse_too_many_bots(network)
end

--- Evaluate undersupply based on latest bot data without consuming dirty flag (runs even if suggestions paused)
--- @param player_table PlayerData
--- @param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
--- @param consume_flag boolean Whether to consume the dirty flag (default: false)
--- @return boolean True if something was evaluated, false if skipped due to not dirty
function Suggestions:evaluate_player_undersupply(player_table, bot_deliveries, consume_flag)
  if not player_table then return false end
  -- Only proceed if undersupply capability is dirty
  local dirty = capability_manager.consume_dirty(player_table, "undersupply")
  if not dirty then return false end
  local network = player_table.network
  if not network then return false end

  local excessivedemand = undersupply.analyse_demand_and_supply(network, bot_deliveries)
  self:set_cached_list("undersupply", excessivedemand)
  self._current_tick = game.tick
  return true
end

--- Evaluate undersupply for a background network
--- @param network LuaLogisticNetwork The network to evaluate
--- @param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
function Suggestions:evaluate_background_undersupply(network, bot_deliveries)
  local excessivedemand = undersupply.analyse_demand_and_supply(network, bot_deliveries)
  self:set_cached_list("undersupply", excessivedemand)
  self._current_tick = game.tick
end

---@param value number The value to evaluate for urgency
---@param red_threshold number The threshold above which urgency is considered high
function Suggestions:get_urgency(value, red_threshold)
  if value > red_threshold then
    return "high"
  else
    return "low"
  end
end

---@param name string The name of the suggestion to store a data point for
---@param data number The data point to store
function Suggestions:remember(name, data)
  if not self._historydata[name] then
    self._historydata[name] = {}
  end
  table.insert(self._historydata[name], {tick = self._current_tick, data = data})
end

--- Get the maximum value from the historical data for a suggestion
--- @param name string The name of the suggestion to get the maximum value for
--- @return number The maximum value from the historical data
function Suggestions:max_from_history(name)
  local history = self._historydata[name]
  if not history or #history == 0 then return 0 end
  local max_value = 0
  local cutoff = self._current_tick - MAX_HISTORY_TICKS
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.tick < cutoff then
      table.remove(history, i)
    elseif entry.data > max_value then
      max_value = entry.data
    end
  end
  return max_value
end

function Suggestions:clear_suggestions()
  -- Historical data needed to make better suggestions
  self._historydata = {
    [Suggestions.awaiting_charge_key] = nil,
    [Suggestions.storage_low_key] = nil,
    [Suggestions.unfiltered_storage_low_key] = nil,
    [Suggestions.undersupply_key] = nil,
    [Suggestions.mismatched_storage_key] = nil,
    [Suggestions.too_many_bots_key] = nil,
  }
  self._suggestions = {
    [Suggestions.awaiting_charge_key] = nil,
    [Suggestions.storage_low_key] = nil,
    [Suggestions.unfiltered_storage_low_key] = nil,
    [Suggestions.undersupply_key] = nil,
    [Suggestions.mismatched_storage_key] = nil,
    [Suggestions.too_many_bots_key] = nil,
  }
  self._cached_data = {
    [Suggestions.awaiting_charge_key] = nil,
    [Suggestions.storage_low_key] = nil,
    [Suggestions.unfiltered_storage_low_key] = nil,
    [Suggestions.undersupply_key] = nil,
    [Suggestions.mismatched_storage_key] = nil,
    [Suggestions.too_many_bots_key] = nil,
  }
end

--- Clear a single suggestion
--- @param name string The name of the suggestion to clear
function Suggestions:clear_suggestion(name)
  self._suggestions[name] = nil
  self._historydata[name] = nil
  self._cached_data[name] = nil
end

--- Create a suggestion
--- @param suggestion_name string The name of the suggestion to create
--- @param count number The number associated with the suggestion, if applicable
--- @param sprite string The sprite to represent the suggestion visually
--- @param urgency SuggestionUrgency The urgency level of the suggestion
--- @param clickable boolean Whether the suggestion is clickable by the user
--- @param action LocalisedString The action to take based on the suggestion
function Suggestions:create_or_clear_suggestion(suggestion_name, count, sprite, urgency, clickable, action)
  local clickname
  if count > 0 then
    if clickable then
      clickname = suggestion_name
    else
      clickname = nil
    end
    self._suggestions[suggestion_name] = {
      name = suggestion_name,
      sprite = sprite,
      urgency = urgency,
      action = action,
      clickname = clickname,
      count = count
    }
  else
    self:clear_suggestion(suggestion_name)
  end
end

-- Potential issue: Too many bots waiting to charge means we need more RPs
---@param waiting_for_charge_count number The number of bots waiting to charge
function Suggestions:analyse_waiting_to_charge(waiting_for_charge_count)
  local need_rps = (waiting_for_charge_count > 9) and math.ceil(waiting_for_charge_count / 4) or 0
  -- Record the last few numbers so the recommendation does not jump around randomly
  self:remember(Suggestions.awaiting_charge_key, need_rps)

  local suggested_number = self:max_from_history(Suggestions.awaiting_charge_key)
  self:create_or_clear_suggestion(
    Suggestions.awaiting_charge_key,
    suggested_number,
    "entity/roboport",
    self:get_urgency(suggested_number, 100),
    false,
    {"suggestions-row.waiting-to-charge-action", suggested_number}
  )
end

--- Create a suggestion, if the numbers warrant it
--- @param suggestion_name string The name of the suggestion to create
--- @param total_stacks number The total number of stacks available
--- @param free_stacks number The number of free stacks available
function Suggestions:create_storage_capacity_suggestion(suggestion_name, total_stacks, free_stacks)
  local used_capacity = 1 -- No stacks = no capacity
  if total_stacks > 0 then used_capacity = 1 - free_stacks / total_stacks end
  local urgency = self:get_urgency(used_capacity, 0.9)
  local used_rounded = math.floor(used_capacity * 1000)/10
  if used_capacity > 0.7 then
    self:create_or_clear_suggestion(suggestion_name, used_rounded, "entity/storage-chest", urgency, false,
      {"suggestions-row." .. suggestion_name .. "-action", used_rounded})
  else
    self:clear_suggestion(suggestion_name)
  end
end

-- Potential issue #1: Storage chests contain items that do not match the filter
-- Potential issue #2: There is not enough free unfiltered storage space
-- Potential issue #3: Storage chests overall are full, or not enough storage
--- @param network? LuaLogisticNetwork The network being analysed
function Suggestions:analyse_storage(network)
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
    self:create_storage_capacity_suggestion(Suggestions.storage_low_key, all_stacks, free_stacks)
    self:create_storage_capacity_suggestion(Suggestions.unfiltered_storage_low_key, unfiltered_stacks, unfiltered_free_stacks)

    -- Create Mismatched Storage suggestion
    local mismatched_count = #mismatched
    self:create_or_clear_suggestion(Suggestions.mismatched_storage_key, mismatched_count, "entity/storage-chest", "low", true,
      {"suggestions-row.mismatched-storage-action", mismatched_count})
    self:set_cached_list(Suggestions.mismatched_storage_key, mismatched) -- Store the list of mismatched storages
  else
    self:clear_suggestion(Suggestions.mismatched_storage_key)
    self:clear_suggestion(Suggestions.unfiltered_storage_low_key)
    self:clear_suggestion(Suggestions.storage_low_key)
  end
end

-- Analyse whether the player is adding too many bots: rising total with many idle
---@param network? LuaLogisticNetwork
function Suggestions:analyse_too_many_bots(network)
  if not network then
    self:clear_suggestion(Suggestions.too_many_bots_key)
    return
  end
  local total = network.all_logistic_robots or 0
  if total < MIN_TOTAL_BOTS_FOR_SUGGESTION then
    self:clear_suggestion(Suggestions.too_many_bots_key)
    return
  end
  local idle = network.available_logistic_robots or 0

  -- Record total for trend analysis
  self:remember(Suggestions.too_many_bots_key, total)
  local history = self._historydata[Suggestions.too_many_bots_key]
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
    self:clear_suggestion(Suggestions.too_many_bots_key)
    return
  end
  local idle_ratio = (total > 0) and (idle / total) or 0
  if idle_ratio <= 0.5 then
    self:clear_suggestion(Suggestions.too_many_bots_key)
    return
  end

  -- If more than 80% of bots are idle, make it an urgent suggestion
  local urgency = self:get_urgency(idle_ratio, 0.8)
  local idle_rounded = math.floor(idle_ratio * 1000)/10
  self:create_or_clear_suggestion(
    Suggestions.too_many_bots_key,
    idle_rounded,
    "entity/logistic-robot",
    urgency,
    false,
    {"suggestions-row.too-many-bots-action", idle_rounded}
  )
end

return Suggestions