--- Analyse data to provider undersupply information

local undersupply = {}

local utils = require("scripts.utils")
local network_data = require("scripts.network-data")

---@class Undersupply_Accumulator
---@field demand table<string, number> Table of item-quality keys to total demand counts
---@field bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@field net_demand UndersupplyItem[] An unsorted array of items with shortages
---@field ignored_items_for_undersupply table<string, boolean> A list of "item name:quality" to ignore for undersupply suggestion

--- Initialize the cell network accumulator
--- @param accumulator Undersupply_Accumulator The accumulator to initialize
--- @param context table Context data for the initialization
function undersupply.initialise_undersupply(accumulator, context)
  accumulator.demand = {}
  accumulator.bot_deliveries = context.bot_deliveries
  accumulator.net_demand = {}
  accumulator.ignored_items_for_undersupply = context.ignored_items
end

local function is_ignored_for_undersupply(ignored_items, item_name, quality_name)
  if ignored_items and item_name and quality_name then
    local key = utils.get_item_quality_key(item_name, quality_name)
    return ignored_items[key] or false
  end
  return false
end

--- Process one requester to gather demand statistics
--- @param requester LuaEntity The requester entity to process
--- @param accumulator Undersupply_Accumulator The accumulator for gathering statistics
--- @return number Return number of "processing units" consumed, default is 1
function undersupply.process_one_requester(requester, accumulator)
  local consumed = 0
  if requester.valid then
    consumed = 1
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
              consumed = consumed + 1 -- Count 1 processing unit per filter
              local itemtype = filter.value.type
              -- Only track items/entities, not fluids, virtuals, etc
              if itemtype == "item" then
                local item_name = filter.value.name
                ---@type string Filter.value.quality is a string, per https://lua-api.factorio.com/latest/concepts/ItemWithQualityCount.html
                ---@diagnostic disable-next-line: assign-type-mismatch
                local quality_name = filter.value.quality or "normal"
                local requested_count = filter.min or 0
                if requested_count > 0 and not is_ignored_for_undersupply(accumulator.ignored_items_for_undersupply, item_name, quality_name) then
                  local inventory = requester.get_inventory(defines.inventory.chest)
                  if inventory then
                    local item_quality = {name = item_name, quality = quality_name}
                    local current_count = inventory.get_item_count(item_quality)
                    local actual_demand = math.max(0, requested_count - current_count)
                    if actual_demand > 0 then
                      local key = utils.get_item_quality_key(item_name, tostring(quality_name))
                      accumulator.demand[key] = (accumulator.demand[key] or 0) + actual_demand
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
  return consumed
end

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

--- Called when all chunks have been processed
--- @param accumulator Undersupply_Accumulator The accumulator with gathered statistics
--- @param gather GatherOptions Gathering options
--- @param network_id number The network data associated with this processing
function undersupply.all_chunks_done(accumulator, gather, network_id)
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if networkdata then
    -- We've finished processing all requesters, so calculate supply and net demand
    local network = network_data.get_LuaNetwork(networkdata)
    if network and network.valid then
      local total_supply_array = network.get_contents() or {}
      local total_supply = {}
      for _, item_with_quality in pairs(total_supply_array) do
        local quality_name = item_with_quality.quality or "normal" -- ensure plain string
        local key = utils.get_item_quality_key(item_with_quality.name, tostring(quality_name))
        total_supply[key] = item_with_quality.count
      end

      local net_demand = {}
      for key, request in pairs(accumulator.demand) do
        local supply = total_supply[key] or 0
        if request > supply then
          local shortage = request - supply
          local item_name, quality_name = key:match("([^:]+):(.+)")
          local under_way = get_underway(accumulator.bot_deliveries, key) or 0
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
      -- Store the end result
      accumulator.net_demand = net_demand
    end
  end
end

return undersupply