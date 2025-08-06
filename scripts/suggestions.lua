--- Handles suggestions for improving logistics network

local analysis = require("scripts.analysis")

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
local MAX_HISTORY_TICKS = 60*5 -- 5 seconds

--- Table containing all suggestions
---@alias SuggestionsTable table<string, Suggestion?>

---@class Suggestions
---@field _current_cell_tick number The game tick when suggestions were last updated
---@field _current_bot_tick number The game tick when suggestions were last updated
---@field _current_tick number The game tick when suggestions were last updated
---@field _historydata table<string, HistoryData> Historical data needed to make good suggestions
---@field _suggestions SuggestionsTable Table containing all suggestions
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

function Suggestions:clear_suggestions()
  -- Historical data needed to make better suggestions
  self._historydata = {
    ["waiting-to-charge"] = nil,
    ["insufficient-storage"] = nil,
    ["supply-shortage"] = nil,

    ["low-logistic-bots"] = nil,
    ["network-congestion"] = nil,
    -- Add other known suggestion types here
  }

  -- Pre-allocate suggestions table with known suggestion types
  self._suggestions = {
    ["waiting-to-charge"] = nil,
    ["insufficient-storage"] = nil,
    ["supply-shortage"] = nil,

    ["low-logistic-bots"] = nil,
    ["network-congestion"] = nil,
    -- Add other known suggestion types here
  }
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
    local urgency = Suggestions:get_urgency(suggested_number, 100)
    self._suggestions["waiting-to-charge"] = {
      name = "Charging Robots",
      sprite = "entity/roboport",
      urgency = urgency,
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
    local used_capacity = 0
    if total_capacity > 0 then
      used_capacity = 1 - total_free / total_capacity
    else
      used_capacity = 0
    end

    if used_capacity >= 0.7 then 
      local urgency = Suggestions:get_urgency(used_capacity, 0.9)
      used_rounded = math.floor(used_capacity * 1000)/10
      self._suggestions["insufficient-storage"] = {
        name = "Insufficient Storage",
        sprite = "entity/storage-chest",
        urgency = urgency,
        evidence = {},
        action = used_rounded .. "% of storage capacity is used.\n Consider adding more storage chests to your network.",
        count = used_capacity
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
  if not self:run_process("cell_data_updated") then
    return -- Not time to update yet
  end

  -- Do we have enough places to charge, or are too many waiting to charge?
  self:analyse_waiting_to_charge()

  -- #TODO: Should chunk this and do it somewhere else. Network chunker?
  -- #TODO: Need to get filter data in same pass to avoid overhead
  -- #TODO: Show the free/occupied percentage in the normal Storage tooltip too
  self:analyse_storage_fullness(network)
end

--- Call when the data about bots has been udpated
--- @param network? LuaLogisticNetwork The network being analysed
--- @param run_undersupply boolean Whether to run the undersupply analysis
function Suggestions:bots_data_updated(network, run_undersupply)
  if not self:run_process("bot_data_updated") then
    return -- Not time to update yet
  end

  if network and run_undersupply then
    analysis.analyse_demand_and_supply(network)
  end
end

return Suggestions