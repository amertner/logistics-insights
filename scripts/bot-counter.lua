local bot_counter = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local chunker = require("scripts.chunker")
local utils = require("scripts.utils")

-- Cache frequently used functions and values for performance
local pairs = pairs
local accumulate_quality = utils.accumulate_quality
local distance = utils.distance
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup
local seen_bot_this_pass = 2
local TOP_TRIPS = network_data.TOP_TRIPS
local seen_bot_last_pass = 1

--- @class Accumulator -- Used by the chunker to accumulate data over multiple passes
--- @field delivering_bots number
--- @field picking_bots number
--- @field item_deliveries table<string, DeliveryItem> The list of current deliveries
--- @field last_seen table<number, number> -- Tracks bots seen in the last pass
--- @field just_seen table<number, number> -- Tracks bots seen in the this pass
--- @field delivering_bot_qualities QualityTable
--- @field picking_bot_qualities QualityTable
--- @field other_bot_qualities QualityTable
--- @field networkdata LINetworkData|nil Cached network data, fetched once per pass
--- @field current_tick number The tick the pass started, which stamps everything seen during it

--- Keep an item's longest trips, longest first, with at most one per destination so a route
--- that is used again and again doesn't fill the list. Trips to a destination already listed
--- are counted, so it's known which long trips happen regularly
--- @param history_order DeliveredItems
--- @param item_key string The history key of the item
--- @param dist number The trip distance
--- @param from MapPosition Where the trip started
--- @param to MapPosition Where the trip ended
--- @param exact boolean True if `from` is the pickup chest rather than an estimate
--- @param tracked boolean|nil True if the bot was already being watched, so an estimated start
---   is at most one scan pass of flight out
--- @param tick number When the trip was last seen
--- @param ignored_trips table<string, IgnoredTrip>|nil Trips accepted as expected, which are not listed
local function record_top_trip(history_order, item_key, dist, from, to, exact, tracked, tick, ignored_trips)
  local trips = history_order.top_trips
  if not trips then
    trips = {}
    history_order.top_trips = trips
  end
  local count = #trips

  -- Same destination as one already listed: count it, and keep whichever trip is longer.
  -- Checked first, as a repeat of the shortest trip listed would otherwise be turned away below
  for i = 1, count do
    local trip = trips[i]
    if trip.to_x == to.x and trip.to_y == to.y then
      trip.deliveries = (trip.deliveries or 1) + 1
      trip.last_tick = tick
      if dist > trip.dist then
        trip.dist, trip.from_x, trip.from_y, trip.exact = dist, from.x, from.y, exact
        trip.tracked = tracked or nil
        -- Now longer, it may need to move up the list
        local pos = i
        while pos > 1 and trips[pos - 1].dist < dist do
          trips[pos], trips[pos - 1] = trips[pos - 1], trips[pos]
          pos = pos - 1
        end
        history_order.top_dist = trips[1].dist
      end
      return
    end
  end

  -- Most trips are no longer than any already kept
  if count >= TOP_TRIPS and dist <= trips[count].dist then return end
  if ignored_trips and ignored_trips[network_data.trip_ignore_key(item_key, to.x, to.y)] then return end

  local pos = count + 1
  while pos > 1 and trips[pos - 1].dist < dist do
    pos = pos - 1
  end
  table.insert(trips, pos, { dist = dist, from_x = from.x, from_y = from.y, to_x = to.x, to_y = to.y,
    exact = exact, tracked = tracked or nil, deliveries = 1, last_tick = tick })
  trips[TOP_TRIPS + 1] = nil
  history_order.top_dist = trips[1].dist
end

--- Add a completed delivery order to the history storage
--- @param delivery_history table<string, DeliveredItems> The delivery history storage table
--- @param order BotDeliveringInFlight The completed order
--- @param ignored_trips table<string, IgnoredTrip>|nil Long trips accepted as expected, which are not listed
local function add_delivered_order_to_history(delivery_history, order, ignored_trips)
  local key = utils.get_item_quality_key(order.item_name, order.quality_name)
  if not delivery_history[key] then
    -- It's the first time this item has been delivered
    delivery_history[key] = {
      item_name = order.item_name,
      quality_name = order.quality_name,
      count = 0,
      deliveries = 0,
      dist_count = 0,
      dist_exact = 0,
      dist_sum = 0,
      avg_dist = 0,
      max_dist = 0,
      top_dist = 0,
      ignored_count = network_data.count_ignored_trips(ignored_trips, order.item_name, order.quality_name),
    }
  end

  local history_order = delivery_history[key]
  local order_count = order.count
  history_order.count = (history_order.count or 0) + order_count

  history_order.deliveries = (history_order.deliveries or 0) + 1

  -- Distance is averaged per delivery, not per item, so bulk short trips can't drown out long ones.
  -- Fields may be missing on history recorded before trip distance was tracked.
  local trip_dist = order.trip_dist
  if trip_dist then
    local dist_count = (history_order.dist_count or 0) + 1
    local dist_sum = (history_order.dist_sum or 0) + trip_dist
    history_order.dist_count = dist_count
    history_order.dist_sum = dist_sum
    history_order.avg_dist = dist_sum / dist_count
    if order.trip_exact then
      history_order.dist_exact = (history_order.dist_exact or 0) + 1
    end
    network_data.record_trip_distance(history_order, trip_dist)
    if trip_dist > (history_order.max_dist or 0) then
      history_order.max_dist = trip_dist
    end
    -- Keep both ends of the longest trips so they can be shown on the map
    record_top_trip(history_order, key, trip_dist, order.trip_from, order.targetpos, order.trip_exact or false,
      order.trip_tracked, order.last_seen, ignored_trips)
  end
end

--- Keep track of how many items of each type is being delivered right now
--- @param item_name string The name of the item being delivered
--- @param quality string The quality name of the item
--- @param count number The number of items being delivered
--- @param item_deliveries table<string, DeliveryItem> The list of current deliveries
local function add_item_to_current_deliveries(item_name, quality, count, item_deliveries)
  local key = utils.get_item_quality_key(item_name, quality)
  if item_deliveries[key] == nil then
    -- Order not seen before
    item_deliveries[key] = {
      item_name = item_name,
      quality_name = quality,
      count = count,
    }
  else -- This item is already being delivered by another bot
    item_deliveries[key].count = item_deliveries[key].count + count
  end
end

--- Add the bot and order to the list of things being delivered for the purpose of calculating history
--- @param networkdata LINetworkData The network data to update
--- @param unit_number number The unique identifier of the robot
--- @param order table The robot's delivery order
--- @param item_name string The name of the item being delivered
--- @param quality string The quality name of the item
--- @param count number The number of items being delivered
--- @param current_tick number The current game tick
--- @param bot LuaEntity|nil The robot, whose position estimates the trip start when the pickup was missed
--- @param tracked boolean True if the bot was already being watched in the previous pass
local function add_bot_to_active_deliveries(networkdata, unit_number, order, item_name, quality, count, current_tick, bot, tracked)
  local botorder = networkdata.bot_active_deliveries[unit_number]
  -- Hoist target and position to avoid repeated table lookups
  local target = order.target
  local target_pos = target and target.position

  if botorder then
    -- We have an existing order for this bot. A different destination or a different item
    -- means the one we were following finished unseen and this is a new one
    local changed = (botorder.targetpos and target_pos and
        (botorder.targetpos.x ~= target_pos.x or botorder.targetpos.y ~= target_pos.y))
      or botorder.item_name ~= item_name or botorder.quality_name ~= quality
    if changed then
      add_delivered_order_to_history(networkdata.delivery_history, botorder, networkdata.ignored_trips)
      networkdata.delivery_history_gen = (networkdata.delivery_history_gen or 0) + 1
      networkdata.bot_active_deliveries[unit_number] = nil
      botorder = nil -- Fall through and start following the new one from this pass, not the next
    else
      -- Just note that we've seen this order again
      botorder.last_seen = current_tick
    end
  end
  if not botorder then
    -- No order for this bot, so add it, measuring the trip from where it picked up this item
    local trip_from, trip_exact
    local pickups = networkdata.bot_pickup_positions
    local pickup = pickups and pickups[unit_number]
    if pickup then
      pickups[unit_number] = nil
      -- Quality counts too: a bot's order can change between passes, and the chest it took normal
      -- plates from says nothing about where the legendary ones it now carries came from
      if pickup.item_name == item_name and pickup.quality_name == quality then
        -- Copy the position out rather than keeping the whole record, which also holds the item
        -- it matched on and when it was seen, neither of which belongs in a saved delivery
        trip_from = { x = pickup.x, y = pickup.y }
        trip_exact = true
      end
    end
    if not trip_from and bot then
      -- Pickup not seen, so estimate from where the bot is now. It has already flown part
      -- of the way, so this is a lower bound, short by at most one scan interval of flight
      trip_from = bot.position
    end
    local trip_dist = (trip_from and target_pos) and distance(trip_from, target_pos) or nil
    -- An estimated start is only a near miss if we were already watching this bot last pass: it
    -- can then have flown at most one pass unseen. A bot we had never looked at could have been
    -- flying for any length of time before we first saw it
    local trip_tracked = (trip_dist and not trip_exact and tracked) or nil
    networkdata.bot_active_deliveries[unit_number] = {
      item_name = item_name,
      quality_name = quality,
      count = count,
      last_seen = current_tick,
      targetpos = target_pos,
      trip_dist = trip_dist,
      trip_from = trip_dist and trip_from or nil,
      trip_exact = trip_dist and trip_exact or nil,
      trip_tracked = trip_tracked,
    }
  end
end

--- Remember where a bot is picking up, so the trip distance can be calculated when its delivery starts
--- @param networkdata LINetworkData The network being processed
--- @param unit_number number The unique identifier of the robot
--- @param order table The robot's pickup order
--- @param item_name string The name of the item being picked up
--- @param current_tick number The current game tick
local function record_pickup_position(networkdata, unit_number, order, item_name, current_tick)
  local target = order.target
  local pos = target and target.position
  if not pos then return end
  -- Read here rather than in the caller, which only works the quality out for deliveries
  local qi = order.target_item and order.target_item.quality
  local quality_name = (qi and qi.name) or "normal"

  local pickups = networkdata.bot_pickup_positions
  if not pickups then
    pickups = {}
    networkdata.bot_pickup_positions = pickups
  end
  local pending = pickups[unit_number]
  if pending and pending.x == pos.x and pending.y == pos.y
    and pending.item_name == item_name and pending.quality_name == quality_name then
    -- Same pickup seen again, avoid allocating a new record
    pending.seen = current_tick
  else
    pickups[unit_number] = { x = pos.x, y = pos.y, item_name = item_name,
      quality_name = quality_name, seen = current_tick }
  end
end

--- The bot is not delivering an order; check if the bot finished a prior delivery
--- and update the history accordingly
--- @param networkdata LINetworkData The network being processed
--- @param unit_number number The unique identifier of the robot
--- @param show_history boolean Whether history tracking is enabled
local function check_if_no_order_bot_finished_delivery(networkdata, unit_number, show_history)
  -- The bot has a delivery interval but no delivery, so it's finished or just gone
  local delivered_order = networkdata.bot_active_deliveries[unit_number]
  if delivered_order then
    if show_history then
      add_delivered_order_to_history(networkdata.delivery_history, delivered_order, networkdata.ignored_trips)
      networkdata.delivery_history_gen = (networkdata.delivery_history_gen or 0) + 1
    end

    -- Remove from active deliveries being tracked
    networkdata.bot_active_deliveries[unit_number] = nil
  end
end

--- This function is called by the chunker once for every bot in the list
--- @param bot LuaEntity The robot entity to process
--- @param accumulator Accumulator The data accumulator containing counters and bot lists
--- @param gather GatherOptions for what to gather
--- @param network_id number The network data associated with this chunker
--- @return number Return number of "processing units" consumed, default is 1
local function process_one_bot(bot, accumulator, gather, network_id)
  local consumed = 0
  if bot and bot.valid then
    local unit_number = bot.unit_number
    if not unit_number then
      -- No unit number, so we can't track this bot
      return 0
    end
    -- Fetched on the first bot of the pass and kept for the rest of it, so every delivery seen
    -- across its chunks carries the same tick. Pruning compares that against last_scanned_tick,
    -- which is only stamped once the whole pass is over
    local networkdata = accumulator.networkdata
    if not networkdata then
      networkdata = network_data.get_networkdata_fromid(network_id)
      if not networkdata then return 0 end
      accumulator.networkdata = networkdata
      accumulator.current_tick = game.tick
    end
    consumed = 1
    if accumulator.last_seen[unit_number] then
      -- Mark bots seen in the last pass as seen again
      accumulator.last_seen[unit_number] = seen_bot_this_pass
    else
      -- Mark this bot as seen for the first time
      accumulator.just_seen[unit_number] = seen_bot_last_pass
    end
    -- Track the bot's quality (skip API call if quality data not needed)
    local quality
    if gather.quality then
      quality = (bot.quality and bot.quality.name) or "normal"
    end

    local order = bot.robot_order_queue[1] or nil
    if order then
      if order.type == defines_robot_order_type_deliver then
        accumulator.delivering_bots = accumulator.delivering_bots + 1
        if quality then accumulate_quality(accumulator.delivering_bot_qualities, quality, 1) end
      elseif order.type == defines_robot_order_type_pickup then
        accumulator.picking_bots = accumulator.picking_bots + 1
        if quality then accumulate_quality(accumulator.picking_bot_qualities, quality, 1) end
      end

      if order.target_item and order.target_item.name then
        -- Hoist target item and its quality fields to reduce repeated table indexing
        local target_item = order.target_item
        if target_item then
          local item_name = target_item.name.name -- string item prototype name
          -- For Deliveries, record the item
          if order.type == defines_robot_order_type_deliver and item_name then
            local item_count = order.target_count or 0
            local qi = target_item.quality
            local item_quality = (qi and qi.name) or "normal"

            -- Record current deliveries
            add_item_to_current_deliveries(item_name, item_quality, item_count, accumulator.item_deliveries)
            -- Record delivery for history purposes. Only worth tracking when history is being
            -- gathered: bot_active_deliveries exists to feed it, and following an order whose
            -- completion is never recorded would write history this network was not asked for
            if gather.history then
              add_bot_to_active_deliveries(networkdata, unit_number, order, item_name, item_quality, item_count,
                accumulator.current_tick, bot, accumulator.last_seen[unit_number] ~= nil)
            end
          else
            if gather.history and order.type == defines_robot_order_type_pickup then
              record_pickup_position(networkdata, unit_number, order, item_name, accumulator.current_tick)
            end
            -- Check if the bot was delivering last time we saw it, and record the delivery
            check_if_no_order_bot_finished_delivery(networkdata, unit_number, gather.history)
          end
        end
      else
        -- This is a situation that should not occur: we have an order but no target item. Clear it.
        check_if_no_order_bot_finished_delivery(networkdata, unit_number, gather.history)
      end
    else
      -- No orders, check if it's because the bot has finished its delivery
      check_if_no_order_bot_finished_delivery(networkdata, unit_number, gather.history)
      -- An idle bot is not on its way to deliver anything it picked up earlier
      local pickups = networkdata.bot_pickup_positions
      if pickups and pickups[unit_number] then
        pickups[unit_number] = nil
      end
      if quality then accumulate_quality(accumulator.other_bot_qualities, quality, 1) end
    end
  end
  return consumed
end

--- Reset counters to be able to process a list of data in chunks
--- @param accumulator Accumulator The data accumulator to reset
--- @param last_seen table<number,number>|nil The list of bots seen in the last pass (nil if first pass))
local function bot_initialise_chunking(accumulator, last_seen)
  accumulator.delivering_bots = 0
  accumulator.picking_bots = 0
  accumulator.item_deliveries = {} -- Reset deliveries
  accumulator.last_seen = last_seen or {} -- The list of bots seen in the last pass
  accumulator.just_seen = {} -- The list of bots first seen this pass
  accumulator.delivering_bot_qualities = {}
  accumulator.picking_bot_qualities = {}
  accumulator.other_bot_qualities = {} -- Gather quality of bots doing anything else
  accumulator.networkdata = nil -- Re-fetched on the first bot of the new pass
  accumulator.current_tick = 0
end

--- This function is called when all chunks are done processing, ready for a new chunk
--- @param accumulator Accumulator The data accumulator containing all gathered statistics
--- @param gather GatherOptions for what to gather
--- @param network_id number The network data to update with results
local function bot_chunks_done(accumulator, gather, network_id)
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if networkdata then
    networkdata.bot_items["delivering"] = accumulator.delivering_bots or nil
    networkdata.bot_items["picking"] = accumulator.picking_bots or nil
    networkdata.bot_deliveries = accumulator.item_deliveries or {}
    networkdata.bot_deliveries_gen = (networkdata.bot_deliveries_gen or 0) + 1
    networkdata.delivering_bot_qualities = accumulator.delivering_bot_qualities or {}
    networkdata.picking_bot_qualities = accumulator.picking_bot_qualities or {}
    networkdata.other_bot_qualities = accumulator.other_bot_qualities or {}
      -- Sum all of the qualities gathered by bot-counter, plus idle ones, to get the totals
    local total_bot_qualities = {}
    if prototypes and prototypes.quality and prototypes.quality.normal then
      local quality = prototypes.quality.normal
      while quality and quality.name do
        local qname = quality.name
        local amount = (networkdata.idle_bot_qualities[qname] or 0)
          + (networkdata.picking_bot_qualities[qname] or 0)
          + (networkdata.delivering_bot_qualities[qname] or 0)
          + (networkdata.other_bot_qualities[qname] or 0)
        total_bot_qualities[qname] = amount
        -- Go to the next higher quality
        quality = quality.next
      end
    end
    networkdata.total_bot_qualities = total_bot_qualities

    -- Carry bots forward whether or not anything is being delivered, so the next pass can tell a
    -- bot it has looked at before from one it is seeing for the first time
    if accumulator.last_seen then
      for unit_number, seen in pairs(accumulator.last_seen) do
        if seen == seen_bot_this_pass then
          -- We saw this bot in the last pass
          accumulator.just_seen[unit_number] = seen_bot_last_pass
        else
          -- We did not see this bot in the last pass, so it probably finished its delivery
          check_if_no_order_bot_finished_delivery(networkdata, unit_number, gather.history)
        end
      end
    end
    -- Save the last-seen list so it can be used in the next pass. Only a pass that follows
    -- deliveries counts as having watched the bots: a background pass may be a whole refresh
    -- interval old, and a trip started after it must not claim to be at most one pass out
    networkdata.last_pass_bots_seen = gather.history and accumulator.just_seen or {}
    network_data.prune_old_data(networkdata, false)
  end
end

--- Process data gathered so far and start over
--- @param networkdata LINetworkData|nil
function bot_counter.restart_counting(networkdata)
  if networkdata then
    networkdata.bot_chunker:reset(networkdata.id, bot_initialise_chunking, bot_chunks_done)
  end
end

--- PROCESSING A PLAYER NETWORK, AKA FOREGROUND

---@param networkdata LINetworkData
---@param network LuaLogisticNetwork
function bot_counter.init_foreground_processing(networkdata, network)
  local gather_options = {}

  -- Any player in the network means the bots have to be counted for the Activity row. History is
  -- extra, and only gathered when at least one of them shows the history row
  for idx, _ in pairs(networkdata.players_set) do
    local player_table = player_data.get_player_table(idx)
    if player_table then
      gather_options.delivering = true
      if player_table.settings.show_history then
        -- At least one player in the network shows the history row
        gather_options.history = true
      end
    end
  end

  if gather_options.delivering or gather_options.history then
    gather_options.quality = global_data.gather_quality_data()
    local net = network
    networkdata.bot_chunker:initialise_chunking(networkdata.id,
      function() return net.valid and net.logistic_robots or {} end,
      networkdata.last_pass_bots_seen, gather_options, bot_initialise_chunking, global_data.CHUNK_DIVISOR, "bot")
  else
    networkdata.bot_items["delivering"] = nil
    networkdata.bot_items["picking"] = nil
  end
end

--- BACKGROUND NETWORK PROCESSING

-- Initialise background processing of a network
---@param networkdata LINetworkData
---@param network LuaLogisticNetwork
function bot_counter.init_background_processing(networkdata, network)
  -- Initialise the chunker for background processing
  local gather_options = {}
  gather_options.quality = global_data.gather_quality_data()

  local net = network
  networkdata.bot_chunker:initialise_chunking(networkdata.id,
    function() return net.valid and net.logistic_robots or {} end,
    networkdata.last_pass_bots_seen, gather_options, bot_initialise_chunking, global_data.CHUNK_DIVISOR, "bot")
end

--- NETWORK SCANNING IN CHUNKS ---

---@param networkdata LINetworkData|nil
---@return boolean True if the network is fully processed, false if there is more data to process
function bot_counter.is_scanning_done(networkdata)
  if not networkdata then
    return true
  end

  local bot_chunker = networkdata.bot_chunker
  if not bot_chunker then
    return true
  end

  return bot_chunker:is_done_processing()
end

-- Process a single chunk of background network data
---@param networkdata LINetworkData
function bot_counter.process_next_chunk(networkdata)
  -- Process the background network data
  networkdata.bot_chunker:process_chunk(process_one_bot)
  if networkdata.bot_chunker:needs_finalisation() then
    networkdata.bot_chunker:finalise_run(bot_chunks_done)
  end
  return true
end

return bot_counter
