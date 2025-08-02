--- Handles suggestions for improving logistics network

--- Status codes to maintain state
---@alias SuggestionsStatusCode 0|1|2|3|4
---@class SuggestionsStatusCodes
local suggestions_statuscodes = {
  Undefined = 0,
  Analysing = 1,
  NoIssues = 2,
  IssuesFound = 3,
  Disabled = 4,
}

--- Urgency levels for suggestions
---@alias SuggestionUrgency "high"|"low"

--- Individual suggestion object
---@class Suggestion
---@field name string The name/title of the suggestion
---@field urgency SuggestionUrgency The urgency level of the suggestion
---@field evidence table List of evidence supporting this suggestion

--- Table containing all suggestions
---@alias SuggestionsTable table<string, Suggestion>

---@class Suggestions
---@field _status SuggestionsStatusCode The current status of the suggestions
---@field _statustable table A table to hold status information
---@field _suggestions SuggestionsTable Table containing all suggestions
local Suggestions = {}
Suggestions.__index = Suggestions
script.register_metatable("logistics-insights-Suggestions", Suggestions)

-- Export status codes for external use
Suggestions.StatusCodes = suggestions_statuscodes

function Suggestions.new()
  local self = setmetatable({}, Suggestions)
  self._status = suggestions_statuscodes.Analysing
  self._statustable = {}
  self._suggestions = {}
  return self
end

---@param player_table PlayerData
---@return SuggestionsStatusCode
function Suggestions:get_status(player_table)
  return self._status
end

--- Reset the suggestions state, typically caused by change of network
function Suggestions:reset()
  self._status = suggestions_statuscodes.Analysing
  self._statustable = {}
  self._suggestions = {}
end

return Suggestions