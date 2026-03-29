--- Analyse data to provider undersupply information

local undersupply = {}

local utils = require("scripts.utils")
local network_data = require("scripts.network-data")

local math_max = math.max
local get_item_quality_key = utils.get_item_quality_key

---@class Undersupply_Accumulator
---@field demand table<string, number> Table of item-quality keys to total demand counts
---@field bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@field net_demand UndersupplyItem[] An unsorted array of items with shortages
---@field ignored_items_for_undersupply table<string, boolean> A list of "item name:quality" to ignore for undersupply suggestion
---@field ignore_player_demands boolean True to ignore player demands when calculating undersupply
---@field ignore_buffer_chests_for_undersupply boolean True to ignore buffer chests when calculating undersupply

--- Initialize the cell network accumulator
--- @param accumulator Undersupply_Accumulator The accumulator to initialize
--- @param context table Context data for the initialization
function undersupply.initialise_undersupply(accumulator, context)
  accumulator.demand = {}
  accumulator.bot_deliveries = context.deliveries
  accumulator.net_demand = {}
  accumulator.ignored_items_for_undersupply = context.ignored_items or {}
  accumulator.ignore_player_demands = context.ignore_player_demands
  accumulator.ignore_buffer_chests_for_undersupply = context.ignore_buffer_chests_for_undersupply
end

--- Process one requester to gather demand statistics
--- @param requester LuaEntity The requester entity to process
--- @param accumulator Undersupply_Accumulator The accumulator for gathering statistics
--- @return number Return number of "processing units" consumed, default is 1
function undersupply.process_one_requester(requester, accumulator)
  if requester.valid then
    if accumulator.ignore_player_demands and requester.type == "character" then
      return 0 -- Ignore player demands
    end
    -- Ignore buffer chests if setting is enabled
    if accumulator.ignore_buffer_chests_for_undersupply and requester.type == "logistic-container" and requester.name == "buffer-chest" then
      return 0
    end
    -- If disabled by a circuit condition, ignore the request
    if requester.status == defines.entity_status.disabled_by_control_behavior then
      return 0
    end
    -- Get the logistic point (the actual requester interface)
    local logistic_point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
    if logistic_point then
      local ignored_items = accumulator.ignored_items_for_undersupply
      local inventory_counts  -- Lazy-built lookup: item_quality_key -> count
      -- Iterate through all sections in the logistic point
      local section_count = logistic_point.sections_count
      for section_index = 1, section_count do
        local requests = logistic_point.get_section(section_index)
        if requests and requests.active then
          local section_multiplier = requests.multiplier or 1
          local all_filters = requests.filters
          local filters_count = requests.filters_count
          for i = 1, filters_count do
            local filter = all_filters[i]
            if filter and filter.value then
              local itemtype = filter.value.type
              -- Only track items/entities, not fluids, virtuals, etc
              if itemtype == "item" then
                local item_name = filter.value.name
                ---@type string Filter.value.quality is a string, per https://lua-api.factorio.com/latest/concepts/ItemWithQualityCount.html
                ---@diagnostic disable-next-line: assign-type-mismatch
                local quality_name = filter.value.quality or "normal"
                local requested_count = (filter.min or 0) * section_multiplier
                local key = get_item_quality_key(item_name, quality_name)
                if requested_count > 0 and not ignored_items[key] then
                  -- Build inventory lookup once per requester via get_contents() instead of per-filter get_item_count()
                  if not inventory_counts then
                    local inventory = requester.get_inventory(defines.inventory.chest)
                    if not inventory then return 1 end
                    inventory_counts = {}
                    local contents = inventory.get_contents()
                    for ci = 1, #contents do
                      local stack = contents[ci]
                      local sq = stack.quality or "normal"
                      inventory_counts[get_item_quality_key(stack.name, sq)] = stack.count
                    end
                  end
                  local current_count = inventory_counts[key] or 0
                  local actual_demand = math_max(0, requested_count - current_count)
                  if actual_demand > 0 then
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
  return 1
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
        local key = get_item_quality_key(item_with_quality.name, quality_name)
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