--- Analyse data to provider undersupply information

local undersupply = {}

local utils = require("scripts.utils")

--- Get the number of items currently being delivered by bots
---@param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@param itemkey string The key for the item being delivered
---@return number The count of items currently being delivered
local function get_underway(bot_deliveries, itemkey)
  if bot_deliveries and itemkey then
    local delivery = bot_deliveries[itemkey]
    return (delivery and delivery.count) or 0
  end
  return 0
end

--- Stage 1: Get a list of all requester/filter pairs in the network
---@param network LuaLogisticNetwork The logistics network to get the list for
---@return table<{requester: LuaEntity, filter: LogisticFilter}> List of requester/filter pairs
function undersupply.stage1_get_requesterfilters(network)
  local result = {}
  if not network or not network.requesters then return result end

  -- Iterate through all requester entities in the network
  for _, requester in pairs(network.requesters) do
    if requester and requester.valid then
      -- Get the logistic point (the actual requester interface)
      local logistic_point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
      if logistic_point then
        -- Iterate through all sections in the logistic point
        local section_count = logistic_point.sections_count or 0
        for section_index = 1, section_count do
          local requests = logistic_point.get_section(section_index)
          if requests and requests.active then
            local fc = requests.filters_count or 0
            for i = 1, fc do
              local filter = requests.filters[i]
              if filter and filter.value and filter.value.type == "item" then
                -- Collect requester + filter pair for further processing
                result[#result+1] = {
                  requester = requester,
                  filter = filter,
                }
              end
            end
          end
        end
      end
    end
  end
  return result
end

--- Stage 3: Calculate total demand from a list of requester/filter pairs
--- @param requester_filter_list table<{requester: LuaEntity, filter: LogisticFilter}> List of requester/filter pairs
--- @return table<string, number> Table of item-quality keys to total demand counts
function undersupply.stage3_calculate_demand(requester_filter_list)
  local total_demand = {}
  for _, entry in pairs(requester_filter_list) do
    local requester = entry.requester
    local filter = entry.filter
    if requester and requester.valid and filter and filter.value then
      local itemtype = filter.value.type
      local item_name = filter.value.name
      ---@type string Filter.value.quality is a string, per https://lua-api.factorio.com/latest/concepts/ItemWithQualityCount.html
      ---@diagnostic disable-next-line: assign-type-mismatch
      local quality_name = filter.value.quality or "normal"
      local requested_count = filter.min or 0
      if requested_count > 0 then
        local inventory = requester.get_inventory(defines.inventory.chest)
        if inventory then
          local item_quality = {name = item_name, quality = quality_name}
          local current_count = inventory.get_item_count(item_quality)
          local actual_demand = math.max(0, requested_count - current_count)
          if actual_demand > 0 then
            local key = utils.get_item_quality_key(item_name, tostring(quality_name))
            total_demand[key] = (total_demand[key] or 0) + actual_demand
          end
        end
      end
    end
  end
  return total_demand
end

---@param network LuaLogisticNetwork The logistics network to get the supply for
---@return table<string, number> Table of item-quality keys to total supply counts
function undersupply.stage4_calculate_supply(network)
  if not network then return {} end
  -- Get_contents returns what's in storage, less what is being picked up. This causes a discrepancy in undersupply :(
  local total_supply_array = network.get_contents() or {}
  local total_supply = {}
  for _, item_with_quality in pairs(total_supply_array) do
    local quality_name = item_with_quality.quality or "normal" -- ensure plain string
    local key = utils.get_item_quality_key(item_with_quality.name, tostring(quality_name))
    total_supply[key] = item_with_quality.count
  end
  return total_supply
end

---@param total_demand table<string, number> Table of item-quality keys to total demand counts
---@param total_supply table<string, number> Table of item-quality keys to total supply counts
---@param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@return ItemWithQualityCount[]|nil An array of items with shortages, sorted by shortage, or nil
function undersupply.stage5_calculate_net_demand(total_demand, total_supply, bot_deliveries)
  local net_demand = {}
  for key, request in pairs(total_demand) do
    local supply = total_supply[key] or 0
    if request > supply then
      local shortage = request - supply
      local item_name, quality_name = key:match("([^:]+):(.+)")
      local under_way = get_underway(bot_deliveries, key) or 0
      if under_way > 0 then
        shortage = shortage - under_way
      end
      if shortage > 0 then
        table.insert(net_demand, {
          shortage = shortage,
          item_name = item_name,
          quality_name = quality_name,
          request = request,
          supply = supply,
          under_way = under_way
        })
      end
    end
  end
  return net_demand
end

---@param network LuaLogisticNetwork The logistics network to analyse
---@param bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@return ItemWithQualityCount[]|nil An array of items with shortages, sorted by shortage, or nil
function undersupply.analyse_demand_and_supply(network, bot_deliveries)
  if network then
    -- Where are there shortages, where demand + under way << supply?
    --@type array<ItemWithQualityCount>
    -- Get_contents returns what's in storage, less what is being picked up. This causes a discrepancy in undersupply :(
    local total_supply_array = network.get_contents() -- Get total supply
    local total_demand = {}
    
    -- Iterate through all requester entities in the network
    for _, requester in pairs(network.requesters) do
      if requester.valid then
        -- Get the logistic point (the actual requester interface)
        local logistic_point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
        
        if logistic_point then
          -- Iterate through all sections in the logistic point
          local section_count = logistic_point.sections_count
          for section_index = 1, section_count do
            local requests = logistic_point.get_section(section_index)
            
            if requests and requests.active then
              for i = 1, requests.filters_count do
                local filter = requests.filters[i]
                if filter and filter.value then
                  local itemtype = filter.value.type
                  -- Only track items/entities, not fluids, virtuals, etc
                  if itemtype == "item" then
                    local item_name = filter.value.name
                    ---@type string Filter.value.quality is a string, per https://lua-api.factorio.com/latest/concepts/ItemWithQualityCount.html
                    ---@diagnostic disable-next-line: assign-type-mismatch
                    local quality_name = filter.value.quality or "normal"
                    local requested_count = filter.min or 0
                    if requested_count > 0 then
                      local inventory = requester.get_inventory(defines.inventory.chest)
                      if inventory then
                        local item_quality = {name = item_name, quality = quality_name}
                        local current_count = inventory.get_item_count(item_quality)
                        local actual_demand = math.max(0, requested_count - current_count)
                        if actual_demand > 0 then
                          local key = utils.get_ItemQuality_key(item_quality)
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
      end
    end

    -- Convert supply array to hash table for O(1) lookups
    local total_supply = {}
    for _, item_with_quality in pairs(total_supply_array) do
      local quality_name = item_with_quality.quality or "normal" -- ensure plain string
      local key = utils.get_item_quality_key(item_with_quality.name, tostring(quality_name))
      total_supply[key] = item_with_quality.count
    end

    -- Calculate net demand for each item - create as array for easy sorting
    -- Net demand = requested - (supply + under way)
    local net_demand = {}
    for key, request in pairs(total_demand) do
      local supply = total_supply[key] or 0
      if request > supply then
        local shortage = request - supply
        local item_name, quality_name = key:match("([^:]+):(.+)")
        local under_way = get_underway(bot_deliveries, key) or 0
        if under_way > 0 then
          shortage = shortage - under_way
        end
        if shortage > 0 then
          table.insert(net_demand, {
            shortage = shortage,
            item_name = item_name,
            quality_name = quality_name,
            request = request,
            supply = supply,
            under_way = under_way
          })
        end
      end
    end
    -- Return net demand in the storage for later display
    return net_demand
  else
    -- No network: No shortages
    return nil
  end
end

return undersupply