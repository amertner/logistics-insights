--- Analyse data to provider undersupply information

local undersupply = {}

local utils = require("scripts.utils")
local network_data = require("scripts.network-data")

local math_max = math.max
local get_item_quality_key = utils.get_item_quality_key

-- How long a parsed-requester cache entry stays valid before being rebuilt.
-- 30 seconds at 60 UPS. Filter configurations rarely change, so this is a
-- safe cache lifetime; the inventory contents are still re-fetched every cycle.
local CACHE_TTL_TICKS = 30 * 60

--- Build a cache entry for one requester. Pre-aggregates (item, quality,
--- requested_count) tuples across all sections into a flat array so the hot
--- path can iterate without any per-section/per-filter API calls.
--- @param requester LuaEntity
--- @return CachedRequester|nil
local function build_requester_cache_entry(requester)
  local logistic_point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not logistic_point then return nil end

  -- type and name are immutable per entity (cache key is unit_number, unique
  -- per instance), so once-at-build is correct.
  local entity_type = requester.type
  local skip_kind = nil
  if entity_type == "character" then
    skip_kind = "character"
  elseif entity_type == "logistic-container" and requester.name == "buffer-chest" then
    skip_kind = "buffer-chest"
  end

  local accumulated = {}  -- key -> total requested
  local section_count = logistic_point.sections_count
  for section_index = 1, section_count do
    local requests = logistic_point.get_section(section_index)
    local filters_count = requests and requests.active and requests.filters_count or 0
    if filters_count > 0 then
      local multiplier = requests.multiplier or 1
      local all_filters = requests.filters
      for i = 1, filters_count do
        local filter = all_filters[i]
        if filter and filter.value and filter.value.type == "item" then
          ---@type string Filter.value.quality is a string, per https://lua-api.factorio.com/latest/concepts/ItemWithQualityCount.html
          ---@diagnostic disable-next-line: assign-type-mismatch
          local quality_name = filter.value.quality or "normal"
          local key = get_item_quality_key(filter.value.name, quality_name)
          local requested = (filter.min or 0) * multiplier
          if requested > 0 then
            accumulated[key] = (accumulated[key] or 0) + requested
          end
        end
      end
    end
  end

  local items = {}
  for key, requested in pairs(accumulated) do
    items[#items + 1] = { key = key, requested_count = requested }
  end
  return { refresh_tick = game.tick, items = items, skip_kind = skip_kind }
end

---@class Undersupply_Accumulator
---@field demand table<string, number> Table of item-quality keys to total demand counts
---@field bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@field net_demand UndersupplyItem[] An unsorted array of items with shortages
---@field ignored_items_for_undersupply table<string, boolean> A list of "item name:quality" to ignore for undersupply suggestion
---@field ignore_player_demands boolean True to ignore player demands when calculating undersupply
---@field ignore_buffer_chests_for_undersupply boolean True to ignore buffer chests when calculating undersupply
---@field requester_cache table<number, CachedRequester> Per-network cache injected via context (not per-cycle data)

---@class CachedRequester
---@field refresh_tick integer Tick when this entry was built
---@field items CachedRequestItem[] Pre-aggregated (item-quality, requested_count) tuples across all sections
---@field skip_kind "character"|"buffer-chest"|nil Set once at build time so the hot path can short-circuit before any per-cycle userdata reads

---@class CachedRequestItem
---@field key string Interned item-quality key (item_name:quality_name)
---@field requested_count integer Total requested count, summed across all sections × multipliers

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
  accumulator.requester_cache = context.requester_cache
end

--- Process one requester to gather demand statistics. Uses the per-network
--- requester_cache to skip filter parsing on cache hit.
--- @param requester LuaEntity The requester entity to process
--- @param accumulator Undersupply_Accumulator The accumulator for gathering statistics
--- @return number Return number of "processing units" consumed, default is 1
function undersupply.process_one_requester(requester, accumulator)
  if not requester.valid then return 1 end

  local unit_number = requester.unit_number
  if not unit_number then return 1 end

  local cache = accumulator.requester_cache
  ---@type CachedRequester|nil
  local entry = cache[unit_number]
  local now = game.tick
  if not entry or now - entry.refresh_tick > CACHE_TTL_TICKS then
    entry = build_requester_cache_entry(requester)
    if not entry then return 1 end
    cache[unit_number] = entry
  end

  local skip_kind = entry.skip_kind
  if skip_kind == "character" then
    if accumulator.ignore_player_demands then return 0 end
  elseif skip_kind == "buffer-chest" then
    if accumulator.ignore_buffer_chests_for_undersupply then return 0 end
  end

  -- Status is NOT cached: circuit-controlled requesters can toggle at runtime.
  if requester.status == defines.entity_status.disabled_by_control_behavior then
    return 0
  end

  local items = entry.items
  local n_items = #items
  if n_items == 0 then return 1 end

  -- Inventory contents change every bot delivery, so we read fresh and build
  -- the lookup lazily on the first non-ignored item.
  local inventory_counts
  local ignored_items = accumulator.ignored_items_for_undersupply
  local demand = accumulator.demand

  for i = 1, n_items do
    local item = items[i]
    local key = item.key
    if not ignored_items[key] then
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
      local actual_demand = math_max(0, item.requested_count - current_count)
      if actual_demand > 0 then
        demand[key] = (demand[key] or 0) + actual_demand
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