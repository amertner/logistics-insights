--- Code to calculate suggestions for networks
local suggestions_calc = {}

local SuggestionsMgr = require("scripts.suggestions")
local network_data = require("scripts.network-data")
local utils = require("scripts.utils")
local global_data = require("scripts.global-data")

-- Reusable table for per-chest filter allow-list to reduce allocations
local __allowed_filters = {}

-- Which qualities a storage filter admits, keyed by "<quality>|<comparator>|<ignore higher>".
-- A filter is read back with a comparator, so "≥ uncommon" admits rare too; walking every
-- quality prototype once per distinct filter is far cheaper than once per chest
local __qualities_admitted = {}

---@param fqual string The filter's quality name
---@param comparator string|nil The filter's comparator, "=" when missing
---@param ignore_higher boolean True to admit every quality above the filter's as well
---@return table<string, boolean> Set of admitted quality names
local function qualities_admitted(fqual, comparator, ignore_higher)
  comparator = comparator or "="
  local key = fqual .. "|" .. comparator .. (ignore_higher and "|h" or "")
  local set = __qualities_admitted[key]
  if set then return set end

  set = {}
  local base = prototypes.quality[fqual]
  local level = base and base.level
  if not level then
    -- Unknown quality: the best that can be done is to take the filter at its word
    set[fqual] = true
  else
    for name, quality in pairs(prototypes.quality) do
      local l = quality.level
      if l and (
          (comparator == "=" and l == level)
          or (comparator == "≥" and l >= level)
          or (comparator == ">" and l > level)
          or (comparator == "≤" and l <= level)
          or (comparator == "<" and l < level)
          or (comparator == "≠" and l ~= level)
          or (ignore_higher and l > level)) then
        set[name] = true
      end
    end
  end
  __qualities_admitted[key] = set
  return set
end

local BOT_TREND_WINDOW_TICKS = 60 * 60 -- 60 seconds window for trend (covers multiple background scans)
local MIN_TOTAL_BOTS_FOR_SUGGESTION = 100 -- Ignore small networks for suggesting too many bots

-- A long trip is worth suggesting something about when it is long in itself and much longer than
-- the item's typical trip, which are both settings, and when it is...
local LONG_TRIP_MIN_DELIVERIES = 3 -- ...made regularly, not just once,
-- ...and still happening, so it ages out once fixed. How long it may go unseen follows the
-- age-out setting rather than being a setting of its own, but never falls so low that an ordinary
-- gap between deliveries disqualifies a trip
local LONG_TRIP_MIN_RECENT_TICKS = 3 * 60 * 60
local LONG_TRIP_URGENT_FACTOR = 5 -- Red rather than yellow from this multiple of the minimum
local LONG_TRIP_OTHERS_SHOWN = 3 -- Other items with long trips listed in the tooltip

--- What a network's long trips are judged against. Global for now; per-network overrides belong
--- here, falling back to these
---@class LongTripThresholds
---@field min_tiles number A trip shorter than this is never suggested
---@field median_factor number Multiple of the item's typical trip that counts as much further
---@field urgent_tiles number Red rather than yellow from here
---@field recent_ticks number How long a trip may go unseen and still count as still happening

---@param networkdata LINetworkData
---@return LongTripThresholds|nil thresholds nil when the suggestion is switched off
local function long_trip_thresholds(networkdata)
  local median_factor = global_data.long_trip_median_factor()
  if not median_factor then return nil end
  local min_tiles = global_data.long_trip_min_distance()
  return {
    min_tiles = min_tiles,
    median_factor = median_factor,
    urgent_tiles = min_tiles * LONG_TRIP_URGENT_FACTOR,
    recent_ticks = math.max(global_data.age_out_suggestions_interval_ticks(), LONG_TRIP_MIN_RECENT_TICKS),
  }
end

-- Potential issue: Too many bots waiting to charge means we need more RPs
---@param suggestions Suggestions
---@param waiting_for_charge_count number The number of bots waiting to charge
function suggestions_calc.analyse_waiting_to_charge(suggestions, waiting_for_charge_count)
  local need_rps = (waiting_for_charge_count > 9) and math.ceil(waiting_for_charge_count / 4) or 0
  -- Record the last few numbers so the recommendation does not jump around randomly
  suggestions:remember(suggestions.awaiting_charge_key, need_rps)

  local interval = 150 -- Default is 2.5 minutes
  if global_data.background_refresh_interval_secs() >= 40 then
    -- If background refresh is very slow, look for trends over a longer period of time
    -- so we have at least 4 data points
    interval = global_data.background_refresh_interval_secs() * 4.1
  end
  local suggested_number = suggestions:weighted_min_from_history(SuggestionsMgr.awaiting_charge_key, interval)
  suggestions:create_or_age_suggestion(
    SuggestionsMgr.awaiting_charge_key,
    suggested_number,
    "entity/roboport",
    suggestions:get_urgency(suggested_number, 100),
    false,
    {"suggestions-row.waiting-to-charge-action", suggested_number}
  )
end

--- Create a suggestion, if the numbers warrant it
--- @param suggestions Suggestions The suggestions manager
--- @param suggestion_name string The name of the suggestion to create
--- @param total_stacks number The total number of stacks available
--- @param free_stacks number The number of free stacks available
--- @param ignore_when_none boolean True to make no suggestion when there are no such chests at all
function suggestions_calc.create_storage_capacity_suggestion(suggestions, suggestion_name, total_stacks, free_stacks, ignore_when_none)
  if ignore_when_none and total_stacks == 0 then
    -- The network's setting says a network without such chests is not short of them
    suggestions:clear_suggestion(suggestion_name)
    return
  end
  local used_capacity = 1 -- No stacks = no capacity
  if total_stacks > 0 then used_capacity = 1 - free_stacks / total_stacks end
  local urgency = suggestions:get_urgency(used_capacity, 0.9)
  local used_rounded = math.floor(used_capacity * 1000)/10
  if used_capacity > 0.7 then
    suggestions:create_or_age_suggestion(suggestion_name, used_rounded, "entity/storage-chest", urgency, false,
      {"suggestions-row." .. suggestion_name .. "-action", used_rounded})
  else
    suggestions:age_out_suggestion(suggestion_name)
  end
end

--- Suggest powering unpowered roboports
--- @param suggestions Suggestions The suggestions manager
--- @param unpowered_roboports_list LuaEntity[] List of unpowered roboports
function suggestions_calc.analyse_unpowered_roboports(suggestions, unpowered_roboports_list)
  if unpowered_roboports_list and #unpowered_roboports_list > 0 then
    local unpowered_roboports = #unpowered_roboports_list
    suggestions:create_or_age_suggestion(
      SuggestionsMgr.unpowered_roboports_key,
      unpowered_roboports,
      "entity/roboport",
      "high",
      true,
      {"suggestions-row.unpowered-roboports-action", unpowered_roboports}
    )
    -- Store the list of unpowered roboports for later inspection
    suggestions:set_cached_list(SuggestionsMgr.unpowered_roboports_key, unpowered_roboports_list)
  else
    suggestions:age_out_suggestion(SuggestionsMgr.unpowered_roboports_key)
  end
end

---@class StorageAccumulator
---@field total_stacks number Total number of stacks in all storage chests
---@field free_stacks number Total number of free stacks in all storage chests
---@field unfiltered_total_stacks number Total number of stacks in unfiltered storage chests
---@field unfiltered_free_stacks number Total number of free stacks in unfiltered storage chests
---@field mismatched_storages LuaEntity[] List of storage chests that have items not
---@field ignored_storages_for_mismatch table<number> Set of storage unit IDs to ignore for mismatch detection
---@field ignore_higher_quality_mismatches boolean Whether to ignore higher quality mismatches
---@field ignore_low_storage_when_no_storage boolean Whether to ignore low storage when there is no storage

-- Get ready to analyse storage in chunks
--- @param accumulator StorageAccumulator The accumulator to store results in
function suggestions_calc.initialise_storage_analysis(accumulator, context)
  accumulator.total_stacks = 0
  accumulator.free_stacks = 0
  accumulator.unfiltered_total_stacks = 0
  accumulator.unfiltered_free_stacks = 0
  accumulator.mismatched_storages = {}
  accumulator.ignored_storages_for_mismatch = context.ignored_storages_for_mismatch or {}
  accumulator.ignore_higher_quality_mismatches = context.ignore_higher_quality_mismatches or false
  accumulator.ignore_low_storage_when_no_storage = context.ignore_low_storage_when_no_storage or false
end

--- Process a storage chest for chunked storage analysis
--- @param nstorage LuaEntity The storage chest entity
--- @param accumulator StorageAccumulator The accumulator to store results in
--- @return number Return number of "processing units" consumed, default is 1
function suggestions_calc.process_storage_for_analysis(nstorage, accumulator)
  local consumed = 0
  if nstorage and nstorage.valid then
    consumed = 1
    local ignore_mismatch = nstorage.unit_number and accumulator.ignored_storages_for_mismatch[nstorage.unit_number]
    local inventory = nstorage.get_inventory(defines.inventory.chest)
    -- Count total and free stacks
    if inventory then
      -- Slots behind the bar are not storage: bots cannot use them, so they count neither as
      -- capacity nor as free
      local capacity = #inventory
      if inventory.supports_bar() then
        capacity = math.min(capacity, inventory.get_bar() - 1)
      end
      local free = inventory.count_empty_stacks(false, false)
      accumulator.total_stacks = accumulator.total_stacks + capacity

      -- Build allowed filter set once (O(F))
      local allowed = __allowed_filters
      utils.table_clear(allowed)
      local has_filters = false
      local fcount = nstorage.filter_slot_count or 0
      if fcount > 0 then
        for finx = 1, fcount do
          local filter = nstorage.get_filter(finx)
          if filter then
            has_filters = true
            local fname = filter.name and (filter.name.name or filter.name) or nil
            if fname then
              local fqual = filter.quality and (filter.quality.name or filter.quality) or nil
              local current = allowed[fname]
              if fqual then
                if current ~= true then
                  if not current then current = {}; allowed[fname] = current end
                  -- Admit what the filter's comparator admits, and every higher quality when the
                  -- network's setting says a better item in the chest is not a mismatch
                  for name in pairs(qualities_admitted(fqual, filter.comparator,
                      accumulator.ignore_higher_quality_mismatches)) do
                    current[name] = true
                  end
                end
              else
                allowed[fname] = true -- any quality allowed
              end
            end
          end
        end
      end

      if not ignore_mismatch then
        -- Single pass over inventory for free count and mismatch detection (O(N))
        if has_filters and not inventory.is_empty() and fcount > 0 then
          -- Get everything in inventory, without iterating over each slot
          local stacks = inventory.get_contents()
          for i = 1, #stacks do
            local stack = stacks[i]
            if stack then
              local sname = stack.name
              local rule = allowed[sname]
              if not rule then
                table.insert(accumulator.mismatched_storages, nstorage)
                break
              end
              if rule ~= true then
                if not rule[stack.quality] then
                  table.insert(accumulator.mismatched_storages, nstorage)
                  break
                end
              end
            end
          end
        end
      end -- not ignore_mismatch

      accumulator.free_stacks = accumulator.free_stacks + free
      if not has_filters then
        accumulator.unfiltered_total_stacks = accumulator.unfiltered_total_stacks + capacity
        accumulator.unfiltered_free_stacks = accumulator.unfiltered_free_stacks + free
      end
    end
  end
  return consumed
end

--- Called when all chunks have been processed
--- @param accumulator StorageAccumulator The accumulator with gathered statistics
--- @param gather GatherOptions Gathering options
--- @param network_id number The network data associated with this processing
function suggestions_calc.all_storage_chunks_done(accumulator, gather, network_id)
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if networkdata then
    local suggestions = networkdata.suggestions
    if accumulator then
      -- Create storage capacity suggestions, if the numbers warrant it. The per-network setting
      -- only silences the case where there are no such chests to be low on; full ones still count
      local ignore_when_none = accumulator.ignore_low_storage_when_no_storage
      suggestions_calc.create_storage_capacity_suggestion(
        suggestions, SuggestionsMgr.storage_low_key, accumulator.total_stacks, accumulator.free_stacks, ignore_when_none)
      suggestions_calc.create_storage_capacity_suggestion(
        suggestions, SuggestionsMgr.unfiltered_storage_low_key, accumulator.unfiltered_total_stacks, accumulator.unfiltered_free_stacks, ignore_when_none)

      -- Create Mismatched Storage suggestion
      local mismatched_count = #accumulator.mismatched_storages
      suggestions:create_or_age_suggestion(SuggestionsMgr.mismatched_storage_key, mismatched_count, "entity/storage-chest", "low", true,
        {"suggestions-row.mismatched-storage-action", mismatched_count})
      if mismatched_count > 0 then
         -- Store the list of mismatched storages
         -- If 0, don't clear the previous list as the player may want to inspect it through the aging suggestion
        suggestions:set_cached_list(SuggestionsMgr.mismatched_storage_key, accumulator.mismatched_storages)
      end
    else
      -- Premature completion: We didn't get the data to figure out if there is anything wrong
      suggestions:clear_suggestion(SuggestionsMgr.mismatched_storage_key)
      suggestions:clear_suggestion(SuggestionsMgr.unfiltered_storage_low_key)
      suggestions:clear_suggestion(SuggestionsMgr.storage_low_key)
    end
  end
end

--- Find items that bots regularly carry much further than usual, e.g. to an outpost when most
--- go to a nearby mall. Only the longest listed trips are looked at, so ignored ones are left out
---@param networkdata LINetworkData
---@param thresholds LongTripThresholds|nil What to judge against; worked out from the settings if omitted
---@return {item_name: string, quality: string, index: integer, trip: TripRecord, median: number}[] Worst first
function suggestions_calc.find_long_trips(networkdata, thresholds)
  thresholds = thresholds or long_trip_thresholds(networkdata)
  if not thresholds then return {} end
  local min_tiles, median_factor = thresholds.min_tiles, thresholds.median_factor
  local found = {}
  local recent = game.tick - thresholds.recent_ticks
  for _, entry in pairs(networkdata.delivery_history or {}) do
    local trips = entry.top_trips
    -- The list is longest first, so most items are ruled out by their first trip
    if trips and trips[1] and trips[1].dist >= min_tiles then
      local median = network_data.median_trip(entry)
      if median then
        for i, trip in ipairs(trips) do
          if trip.dist < min_tiles or trip.dist < median_factor * median then break end
          if (trip.deliveries or 1) >= LONG_TRIP_MIN_DELIVERIES and (trip.last_tick or 0) >= recent then
            found[#found + 1] = { item_name = entry.item_name, quality = entry.quality_name or "normal",
              index = i, trip = trip, median = median }
            break -- One per item: its longest trip that qualifies
          end
        end
      end
    end
  end
  table.sort(found, function(a, b) return a.trip.dist > b.trip.dist end)
  return found
end

--- The rich text icon for an item
---@param item_name string
---@param quality string
local function item_icon(item_name, quality)
  if quality == "normal" then return "[item=" .. item_name .. "]" end
  return "[item=" .. item_name .. ",quality=" .. quality .. "]"
end

--- Suggest a closer supply for items that bots regularly carry much further than usual
---@param suggestions Suggestions
---@param networkdata LINetworkData
function suggestions_calc.analyse_long_trips(suggestions, networkdata)
  local thresholds = long_trip_thresholds(networkdata)
  if not thresholds then
    -- Switched off, so drop it straight away rather than leaving it to age out
    suggestions:clear_suggestion(SuggestionsMgr.long_trip_key)
    return
  end
  local found = suggestions_calc.find_long_trips(networkdata, thresholds)
  local worst = found[1]
  if not worst then
    suggestions:age_out_suggestion(SuggestionsMgr.long_trip_key)
    return
  end

  local others = ""
  if #found > 1 then
    -- Each item's icon and distance, e.g. "[item=iron-plate] 603 m, [item=coal] 410 m"
    local list = {""}
    for i = 2, math.min(#found, LONG_TRIP_OTHERS_SHOWN + 1) do
      if #list > 1 then list[#list + 1] = ", " end
      list[#list + 1] = item_icon(found[i].item_name, found[i].quality) .. " "
      list[#list + 1] = utils.format_distances({found[i].trip.dist})
    end
    others = {"", "\n", {"suggestions-row.long-trip-others", list}}
  end
  local dist = math.floor(worst.trip.dist + 0.5)
  local names = utils.get_localised_names({ item_name = worst.item_name, quality_name = worst.quality })
  suggestions:create_or_age_suggestion(
    SuggestionsMgr.long_trip_key,
    dist,
    utils.get_valid_sprite_path("item/", worst.item_name, "entity/logistic-robot"),
    suggestions:get_urgency(dist, thresholds.urgent_tiles - 1),
    true,
    {"suggestions-row.long-trip-action-1icon-2item-3dist-4times-5median-6others",
      item_icon(worst.item_name, worst.quality), names.iname, utils.format_distances({worst.trip.dist}),
      worst.trip.deliveries, utils.format_distances({worst.median}), others}
  )
  -- What a click shows: the worst item's trips, at the one suggested
  suggestions:set_cached_list(SuggestionsMgr.long_trip_key,
    { item_name = worst.item_name, quality = worst.quality, index = worst.index })
end

-- Analyse whether the player is adding too many bots: rising total with many idle
---@param suggestions Suggestions The suggestions manager
---@param network? LuaLogisticNetwork
function suggestions_calc.analyse_too_many_bots(suggestions, network)
  if not network then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end
  local total = network.all_logistic_robots or 0
  if total < MIN_TOTAL_BOTS_FOR_SUGGESTION then
    suggestions:clear_suggestion(SuggestionsMgr.too_many_bots_key)
    -- Prune stale history so it doesn't cause false trends when network grows back
    suggestions:history_in_window(SuggestionsMgr.too_many_bots_key, BOT_TREND_WINDOW_TICKS)
    return
  end
  local idle = network.available_logistic_robots or 0

  -- Record total for trend analysis
  suggestions:remember(SuggestionsMgr.too_many_bots_key, total)
  local history = suggestions:history_in_window(SuggestionsMgr.too_many_bots_key, BOT_TREND_WINDOW_TICKS)
  if #history < 3 then
    return -- Need more samples
  end
  local first, last = history[1].data, history[#history].data
  if last <= first then
    -- Only warn of too many bots if the number is increasing
    suggestions:age_out_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end
  local idle_ratio = (total > 0) and (idle / total) or 0
  if idle_ratio <= 0.5 then
    suggestions:age_out_suggestion(SuggestionsMgr.too_many_bots_key)
    return
  end

  -- If more than 80% of bots are idle, make it an urgent suggestion
  local urgency = suggestions:get_urgency(idle_ratio, 0.8)
  local idle_rounded = math.floor(idle_ratio * 1000)/10
  suggestions:create_or_age_suggestion(
    SuggestionsMgr.too_many_bots_key,
    idle_rounded,
    "entity/logistic-robot",
    urgency,
    false,
    {"suggestions-row.too-many-bots-action", idle_rounded}
  )
end

-- Analyse the trend of idle bots:
-- - whether the player is adding too many bots: rising total with many idle
-- - whether the player needs more bots: all bots busy for a while
---@param suggestions Suggestions The suggestions manager
---@param network? LuaLogisticNetwork
function suggestions_calc.analyse_too_few_bots(suggestions, network)
  if not network then
    suggestions:clear_suggestion(SuggestionsMgr.too_few_bots_key)
    return
  end
  local total = network.all_logistic_robots or 0
  local idle = network.available_logistic_robots or 0

  -- Record idle for trend analysis
  suggestions:remember(SuggestionsMgr.too_few_bots_key, idle)
  -- Look for highest number of idle bots in the window
  local history = suggestions:history_in_window(SuggestionsMgr.too_few_bots_key, BOT_TREND_WINDOW_TICKS)
  if #history < 3 then
    return -- Need more samples
  end
  local highest_idle = idle
  for i = 1, #history do
    if history[i].data > highest_idle then
      highest_idle = history[i].data
    end
  end

  local highest_idle_ratio = (total > 0) and (highest_idle / total) or 0
  if highest_idle_ratio <= 0.02 and total > 0 then
    -- There are bots and 98%+ of them are busy, suggest getting more
    local busy_rounded = math.floor((1-highest_idle_ratio) * 1000)/10
    suggestions:create_or_age_suggestion(
      SuggestionsMgr.too_few_bots_key,
      busy_rounded,
      "entity/logistic-robot",
      "low",
      false,
      {"suggestions-row.too-few-bots-action"}
    )
    return
  else
    suggestions:age_out_suggestion(SuggestionsMgr.too_few_bots_key)
  end
end

return suggestions_calc
