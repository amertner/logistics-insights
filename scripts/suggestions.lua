--- Handles storage of suggestions for improving logistics network

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

function Suggestions:update_tick()
  self._current_tick = game.tick
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

return Suggestions