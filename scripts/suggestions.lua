--- Handles suggestions for improving logistics network

--- Urgency levels for suggestions
---@alias SuggestionUrgency "high"|"low"

--- Individual suggestion object
---@class Suggestion
---@field name string The name/title of the suggestion
---@field count number? The number associated with the suggestion, if applicable
---@field sprite string The sprite to represent the suggestion visually
---@field urgency SuggestionUrgency The urgency level of the suggestion
---@field action string The action to take based on the suggestion
---@field evidence table List of evidence supporting this suggestion

--- Table containing a historical datapoint
---@class HistoryDataEntry
---@field tick number The time when the suggestion was made
---@field data number The number at the time

--- Table containing historical data for a suggestion
--- @alias HistoryData table<HistoryDataEntry>?
local MAX_HISTORY_TICKS = 60*10 -- 10 seconds

--- Table containing all suggestions
---@alias SuggestionsTable table<string, Suggestion?>

---@class Suggestions
---@field _current_tick number The game tick when suggestions were last updated
---@field _historydata table<string, HistoryData> Historical data needed to make good suggestions
---@field _suggestions SuggestionsTable Table containing all suggestions
local Suggestions = {}
Suggestions.__index = Suggestions
script.register_metatable("logistics-insights-Suggestions", Suggestions)

function Suggestions.new()
  local self = setmetatable({}, Suggestions)
  self._current_tick = game.tick
  -- Historical data needed to make better suggestions
  self._historydata = {
    ["waiting-to-charge"] = nil,
    ["low-construction-bots"] = nil,
    ["low-logistic-bots"] = nil,
    ["network-congestion"] = nil,
    ["insufficient-storage"] = nil,
    -- Add other known suggestion types here
  }

  -- Pre-allocate suggestions table with known suggestion types
  self._suggestions = {
    ["waiting-to-charge"] = nil,
    ["low-construction-bots"] = nil,
    ["low-logistic-bots"] = nil,
    ["network-congestion"] = nil,
    ["insufficient-storage"] = nil,
    -- Add other known suggestion types here
  }

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
  for index, entry in ipairs(history) do
    if entry.data > max_value then
      max_value = entry.data
    end
    if entry.tick < self._current_tick - MAX_HISTORY_TICKS then
      -- Remove old entries older than 1 hour
      table.remove(history, index)
    end
  end
  return max_value
end

function Suggestions:clear_suggestion(name)
  self._suggestions[name] = nil
  self._historydata[name] = nil
end

-- Potential issue: Too many bots waiting to charge means we need more RPs
function Suggestions:analyse_waiting_to_charge()
  -- Do we have enough places to charge, or are too many waiting to charge?
  local waiting = storage.bot_items["waiting-for-charge-robot"] or 0
  local need_rps
  if waiting > 9 then
    need_rps = math.ceil(waiting / 3) -- Assume 3 bots will charge in one roboport
  else
    need_rps = 0
  end
  self:remember("waiting-to-charge", need_rps)
  suggested_number = self:max_from_history("waiting-to-charge")
  if suggested_number > 0 then
    -- Bots are charging, and some are waiting
    self._suggestions["waiting-to-charge"] = {
      name = "Charging Robots",
      sprite = "entity/roboport",
      urgency = "high",
      evidence = {},
      count = suggested_number,
      action = "Robots are waiting to charge. Consider adding at least " .. suggested_number .." charging stations or roboports to areas of high traffic."
    }
  else
    self:clear_suggestion("waiting-to-charge")
  end
end

-- Potential issue: Storage chests are full, or not enough storage
--- @param network? LuaLogisticNetwork The network being analysed
function Suggestions:analyse_storage_fullness(network)
  if network and network.storages then
    -- Calculate # of stacks used vs capacity. Partially filled stacks count as full.
    local total_capacity = 0
    local total_free = 0
    for _, storage in pairs(network.storages) do
      if storage.valid then
        local inventory = storage.get_inventory(defines.inventory.chest)
        if inventory then
          total_free = total_free + inventory.count_empty_stacks()
          total_capacity = total_capacity + #inventory
        end
      end
    end
    local available = 0
    if total_capacity > 0 then
      available = total_free / total_capacity
    else
      available = 0
    end

    --self:remember("insufficient-storage", utilization)
    --suggested_number = self:max_from_history("insufficient-storage")

    if available < 0.7 then -- 90% full
      available_rounded = math.floor(available * 1000)/10
      self._suggestions["insufficient-storage"] = {
        name = "Insufficient Storage",
        sprite = "entity/storage-chest",
        urgency = "high",
        evidence = {},
        action = "Only " .. available_rounded .. "% of storage capacity is free.\n Consider adding more storage chests to your network.",
        count = available
      }
    else
      self:clear_suggestion("insufficient-storage")
    end
  else
    self:clear_suggestion("insufficient-storage")
  end
end

--- Call when the data about logistics cells has been udpated
--- @param network? LuaLogisticNetwork The network being analysed
function Suggestions:cells_data_updated(network)
  -- Save the current game tick
  self._current_tick = game.tick
  -- Do we have enough places to charge, or are too many waiting to charge?
  self:analyse_waiting_to_charge()

  -- TODO: Should chunk this and do it somewhere else. Network chunker?
  -- TODO: Need to get filter data in same pass to avoid overhead
  self:analyse_storage_fullness(network)
end

return Suggestions