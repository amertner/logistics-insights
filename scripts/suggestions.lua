--- Handles suggestions for improving logistics network

local undersupply = require("scripts.undersupply")

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

--- Table containing all suggestions
---@alias SuggestionsTable table<string, Suggestion?>

---@class Suggestions
---@field _current_cell_tick number The game tick when suggestions were last updated
---@field _current_bot_tick number The game tick when suggestions were last updated
---@field _current_tick number The game tick when suggestions were last updated
---@field _historydata table<string, HistoryData> Historical data needed to make good suggestions
---@field _suggestions SuggestionsTable Table containing all suggestions
---@field _cached_data table<string, table|nil> Cached data for suggestions to be used in the UI
local Suggestions = {}
Suggestions.__index = Suggestions
script.register_metatable("logistics-insights-Suggestions", Suggestions)

function Suggestions.new()
  local self = setmetatable({}, Suggestions)
  self._current_cell_tick = 0
  self._current_bot_tick = 0
  self._current_tick = 0
  self:clear_suggestions()

  return self
end

--- Reset the suggestions state, typically caused by change of network
function Suggestions:reset()
  self._suggestions = {}
end

--- Retrieve the list of current suggestions
--- @return SuggestionsTable The current suggestions
function Suggestions:get_suggestions()
  return self._suggestions
end

-- Get the list of objects for a specific suggestion so it can be used in the UI
---@param suggestion_name AnyBasic The name of the suggestion to retrieve
---@return table A list of items identified as important to the suggestion
function Suggestions:get_cached_list(suggestion_name)
  if not self._suggestions[suggestion_name] then
    return {} -- No suggestions of this type
  end
  return self._cached_data[suggestion_name]
end

function Suggestions:set_cached_list(suggestion_name, list)
  self._cached_data[suggestion_name] = list
end

function Suggestions:run_process(processname)
  local tick = game.tick
  if processname == "cell_data_updated" then
    if tick - 60 > (self._current_cell_tick or 0) then
      self._current_cell_tick = tick
      self._current_tick = tick
      return true
    end
  elseif processname == "bot_data_updated" then
    if tick - 60 > (self._current_bot_tick or 0) then
      self._current_bot_tick = tick
      self._current_tick = tick
      return true
    end
  end
  return false
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
  if not history or #history == 0 then
    return 0
  end
  local max_value = 0
  local cutoff = self._current_tick - MAX_HISTORY_TICKS
  -- Iterate backwards so removals are safe
  for i = #history, 1, -1 do
    local entry = history[i]
    if entry.tick < cutoff then
      table.remove(history, i)
    else
      if entry.data > max_value then
        max_value = entry.data
      end
    end
  end
  return max_value
end

function Suggestions:clear_suggestions()
  -- Historical data needed to make better suggestions
  self._historydata = {
    ["waiting-to-charge"] = nil,
    ["insufficient-storage"] = nil,
    ["insufficient-unfiltered-storage"] = nil,
    ["supply-shortage"] = nil,
    ["mismatched-storage"] = nil,
  }

  -- Pre-allocate suggestions table with known suggestion types
  self._suggestions = {
    ["waiting-to-charge"] = nil,
    ["insufficient-storage"] = nil,
    ["insufficient-unfiltered-storage"] = nil,
    ["supply-shortage"] = nil,
    ["mismatched-storage"] = nil,
  }
  self._cached_data = {
    ["waiting-to-charge"] = nil,
    ["insufficient-storage"] = nil,
    ["insufficient-unfiltered-storage"] = nil,
    ["supply-shortage"] = nil,
    ["mismatched-storage"] = nil,
  }
end

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
function Suggestions:analyse_waiting_to_charge()
  -- Do we have enough places to charge, or are too many waiting to charge?
  local waiting = storage.bot_items["waiting-for-charge-robot"] or 0
  local need_rps
  if waiting > 9 then
    need_rps = math.ceil(waiting / 4) -- Assume 4 bots will charge in one roboport
  else
    need_rps = 0
  end
  -- Record the last few numbers so the recommendation does not jump around randomly
  self:remember("waiting-to-charge", need_rps)

  local suggested_number = self:max_from_history("waiting-to-charge")
  self:create_or_clear_suggestion("waiting-to-charge", suggested_number, "entity/roboport", Suggestions:get_urgency(suggested_number, 100), false,
    {"suggestions-row.waiting-to-charge-action", suggested_number})
end

--- Create a suggestion, if the numbers warrant it
--- @param suggestion_name string The name of the suggestion to create
--- @param total_stacks number The total number of stacks available
--- @param free_stacks number The number of free stacks available
function Suggestions:create_storage_capacity_suggestion(suggestion_name, total_stacks, free_stacks)
  local used_capacity = 1 -- No stacks = no capacity
  if total_stacks > 0 then
    used_capacity = 1 - free_stacks / total_stacks
  end
  local urgency = Suggestions:get_urgency(used_capacity, 0.9)
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
  local SUGGESTION_mismatch = "mismatched-storage"
  local SUGGESTION_unfiltered = "insufficient-unfiltered-storage"
  local SUGGESTION_storage = "insufficient-storage"
  if network and network.storages then
    -- Maintain a list of mismatched storages
    local mismatched = {}
    -- Maintain a count of total and free stacks
    local all_stacks = 0
    local free_stacks = 0
    local unfiltered_stacks = 0
    local unfiltered_free_stacks = 0
    for _, storage in pairs(network.storages) do
      if storage.valid then
        local inventory = storage.get_inventory(defines.inventory.chest)
        -- Count total and free stacks
        if inventory then
          local capacity = #inventory
          local free = inventory.count_empty_stacks()
          all_stacks = all_stacks + capacity
          free_stacks = free_stacks + free

          -- Iterate over filtered to find mismatches
          if storage.filter_slot_count then
            for finx = 1, storage.filter_slot_count do
              -- Check if the filter matches the contents
              local filter = storage.get_filter(finx)
              if filter then
                if inventory and not inventory.is_empty() then
                  local stacks = inventory.get_contents()
                  -- Check if any of the contents does not match the filter
                  local index = 1
                  while index <= #stacks do 
                    local stack = stacks[index]
                    if stack then
                      if stack.name ~= filter.name.name or stack.quality ~= filter.quality.name then
                        -- There are items that do not match the filter
                        table.insert(mismatched, storage)
                        -- Don't check the rest of the stacks
                        break
                      end
                    end
                    index = index + 1
                  end
                end
              else
                -- There is no filter, count unfiltered capacity
                if finx == 1 then -- If there are multiple filters, only count capacity once
                  unfiltered_stacks = unfiltered_stacks + capacity
                  unfiltered_free_stacks = unfiltered_free_stacks + free
                end
              end
            end
          end
        end
      end
    end

    -- Create storage capacity suggestions, if the numbers warrant it
    self:create_storage_capacity_suggestion(SUGGESTION_storage, all_stacks, free_stacks)
    self:create_storage_capacity_suggestion(SUGGESTION_unfiltered, unfiltered_stacks, unfiltered_free_stacks)

    -- Create Mismatched Storage suggestion
    local mismatched_count = #mismatched
    self:create_or_clear_suggestion(SUGGESTION_mismatch, mismatched_count, "entity/storage-chest", "low", true,
      {"suggestions-row.mismatched-storage-action", mismatched_count})
    self:set_cached_list(SUGGESTION_mismatch, mismatched) -- Store the list of mismatched storages
  else
    self:clear_suggestion(SUGGESTION_mismatch)
    self:clear_suggestion(SUGGESTION_unfiltered)
    self:clear_suggestion(SUGGESTION_storage)
  end
end

--- Call when the data about logistics cells has been udpated
--- @param network? LuaLogisticNetwork The network being analysed
function Suggestions:cells_data_updated(network)
  if not self:run_process("cell_data_updated") then
    return -- Not time to update yet
  end

  -- Do we have enough places to charge, or are too many waiting to charge?
  self:analyse_waiting_to_charge()

  -- Three possible suggestions from analysing storage chests
  self:analyse_storage(network)
end

--- Call when the data about bots has been udpated
--- @param network? LuaLogisticNetwork The network being analysed
--- @param run_undersupply boolean Whether to run the undersupply analysis
function Suggestions:bots_data_updated(network, run_undersupply)
  if not self:run_process("bot_data_updated") then
    return -- Not time to update yet
  end

  if network and run_undersupply then
    undersupply.analyse_demand_and_supply(network)
  end
end

return Suggestions