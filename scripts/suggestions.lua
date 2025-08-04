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
    if tick + 60 > (self._current_cell_tick or 0) then
      self._current_cell_tick = tick
      self._current_tick = tick
      return true
    end
  elseif processname == "bot_data_updated" then
    if tick + 60 > (self._current_bot_tick or 0) then
      self._current_bot_tick = tick
      self._current_tick = tick
      return true
    end
  end
  return false
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
    local urgency
    if suggested_number > 100 then
      urgency = "high"
    else
      urgency = "low"
    end
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
    local available = 0
    if total_capacity > 0 then
      available = total_free / total_capacity
    else
      available = 0
    end

    --self:remember("insufficient-storage", utilization)
    --suggested_number = self:max_from_history("insufficient-storage")

    if available < 0.7 then 
      local urgency
      if available < 0.1 then
        urgency = "high"
      else
        urgency = "low"
      end
      available_rounded = math.floor(available * 1000)/10
      self._suggestions["insufficient-storage"] = {
        name = "Insufficient Storage",
        sprite = "entity/storage-chest",
        urgency = urgency,
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
  if not self:run_process("cell_data_updated") then
    return -- Not time to update yet
  end

  -- Do we have enough places to charge, or are too many waiting to charge?
  self:analyse_waiting_to_charge()

  -- TODO: Should chunk this and do it somewhere else. Network chunker?
  -- TODO: Need to get filter data in same pass to avoid overhead
  -- TODO: Show the free/occupied percentage in the normal Storage tooltip too
  self:analyse_storage_fullness(network)
end

-- Create a table to store combined (name/quality) keys for reduced memory fragmentation
local item_quality_keys = {}

--- Get a cached delivery key for item name and quality combination
--- @param item_name string The name of the item
--- @param quality string The quality name (e.g., "normal", "uncommon", etc.)
--- @return string The cached delivery key
local function get_item_quality_key(item_name, quality)
  local cache_key = item_name .. ":" .. quality
  local key = item_quality_keys[cache_key]
  if not key then
    key = cache_key
    item_quality_keys[cache_key] = key
  end
  return key
end

function Suggestions:analyse_demand_and_supply(network)
  local function get_underway(itemkey)
    if storage.bot_deliveries then
      local delivery = storage.bot_deliveries[itemkey]
      return (delivery and delivery.count) or 0
    end
  end

  if network and network.storages then
    -- Where are there shortages, where demand + under way << supply?
    --@type array<ItemWithQualityCount>
    local total_supply_array = network.get_contents() -- Get total supply
    local total_demand = {}
    
    -- Iterate through all requester entities in the network
    for _, requester in pairs(network.requesters) do
      if requester.valid then
        -- Get the logistic point (the actual requester interface)
        local logistic_point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
        
        if logistic_point then
          -- Get active requests from the logistic point
          local requests = logistic_point.get_section(1) -- Section 1 contains the requests
          
          if requests then
            for i = 1, requests.filters_count do
              local filter = requests.filters[i]
              if filter and filter.value then
                local type = filter.value.type
                -- Only track items/entities, not fluids, virtuals, etc
                if type == "item" or type == "entity" then
                  local item_name = filter.value.name
                  local quality = filter.value.quality or "normal"
                  local requested_count = filter.min
                  
                  -- Calculate actual demand (requested - already in requester)
                  local inventory = requester.get_inventory(defines.inventory.linked_container_main)
                  if inventory then
                    item_quality = {name = item_name, quality = quality}
                    local current_count = inventory.get_item_count(item_quality)
                    local actual_demand = math.max(0, requested_count - current_count)
                    
                    if actual_demand > 0 then
                      local key = get_item_quality_key(item_name, quality)
                      total_demand[key] = (total_demand[key] or 0) + actual_demand
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    -- Convert supply array to hash table for O(1) lookups
    local total_supply = {}
    for _, item_with_quality in pairs(total_supply_array) do
      local key = get_item_quality_key(item_with_quality.name, item_with_quality.quality or "normal")
      total_supply[key] = item_with_quality.count
    end

    -- Calculate net demand for each item - create as array for easy sorting
    -- Net demand = requested - supply - under way
    local net_demand = {}
    for key, request in pairs(total_demand) do
      local supply = total_supply[key] or 0
      if request > supply then
        local shortage = request - supply
        local item_name, quality = key:match("([^:]+):(.+)")

        -- The key is different, TODO: Change to be the same
        local under_way = get_underway(item_name .. quality) or 0 -- Get the number of items already in transit
        if under_way > 0 then
          shortage = shortage - under_way
        end
        if shortage > 0 then

          table.insert(net_demand, {
            key = key,
            shortage = shortage,
            item_name = item_name,
            quality = quality,
            request = request,
            supply = supply,
            under_way = under_way
          })
        end
      end
    end

    -- Sort by shortage amount (highest first)
    table.sort(net_demand, function(a, b)
      return a.shortage > b.shortage
    end)
    
    local shortages = table_size(net_demand)
    if shortages > 0 then
      local shortage_str = ""
      for i = 1, math.min(5, #net_demand) do
        local shortage_data = net_demand[i]
        shortage_str = shortage_str .. "\n" .. shortage_data.item_name .. " (" .. shortage_data.quality .. "): " .. shortage_data.shortage .. "(Demand: " .. shortage_data.request .. ", Supply: " .. shortage_data.supply .. ", Underway: " .. shortage_data.under_way .. ")"
      end

      self._suggestions["supply-shortage"] = {
        name = "Supply Shortage",
        sprite = "entity/passive-provider-chest",
        urgency = "low",
        evidence = {},
        action = "Some items are requested in larger number than they are available in the network. Consider producing more of those items.\nThe top items are: " .. shortage_str,
        count = shortages
      }
    else
      self:clear_suggestion("supply-shortage")
    end
  else
    self:clear_suggestion("supply-shortage")
  end
end

--- Call when the data about bots has been udpated
--- @param network? LuaLogisticNetwork The network being analysed
function Suggestions:bots_data_updated(network)
  if not self:run_process("bot_data_updated") then
    return -- Not time to update yet
  end

  -- Where are there shortages, where demand + under way << supply?
  self:analyse_demand_and_supply(network)
end

return Suggestions