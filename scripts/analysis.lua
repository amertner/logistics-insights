--- Analyse data to provider undersupply information

local analysis = {}

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

local function get_underway(itemkey)
  if storage.bot_deliveries then
    local delivery = storage.bot_deliveries[itemkey]
    return (delivery and delivery.count) or 0
  end
end

function analysis:analyse_demand_and_supply(network)
  if network and network.storages then
    -- Where are there shortages, where demand + under way << supply?
    --@type array<ItemWithQualityCount>
    local total_supply_array = network.get_contents() -- Get total supply
    local total_demand = {item = {}, entity = {}}
    
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
                      total_demand[type][key] = (total_demand[type][key] or 0) + actual_demand
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
    for type, demands in pairs(total_demand) do
      -- item and entity
      for key, request in pairs(demands) do
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
              type = type,
              item_name = item_name,
              quality_name = quality,
              request = request,
              supply = supply,
              under_way = under_way
            })
          end
        end
      end
    end
    -- Store the unsorted net demand in the storage for later display
    storage.undersupply = net_demand
  end
end

return analysis