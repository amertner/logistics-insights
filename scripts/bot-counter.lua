local bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")
local utils = require("scripts.utils")

-- Constants
 -- How many ticks to group deliveries into intervals
 -- Too large: The blocks get very large and take a long time to process
 -- Too small: Too many blocks to process, and a lot of work processing "late" blocks
local INTERVAL_TICKS = 30

-- Storage structures
-- bot_active_deliveries: Tracks bot deliveries organized by expected delivery interval
-- bot_delivery_lookup: Maps bot unit numbers to their interval for faster lookups
-- delivery_history: Stores completed deliveries with their statistics

-- Cache frequently used functions and values for performance
local pairs = pairs
local table_size = table_size
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup

-- Create a table to store combined keys for reduced memory fragmentation
local delivery_keys = {}
-- Cache the current speed of logistics bots to avoid recalculating it every time
local cached_logistic_bot_speed = nil
local mystats = nil

local function clear_mystats()
  mystats = {
    history_intervals = 0,
    history_interval_items = 0,
    history_interval_ok = 0,
    history_interval_notyet = 0,

    late_bots = 0,
    estimate_drifts = 0,
    stationary_mystery = 0,
    was_charged = 0,
    finished_deliveries_no_order = 0,
    finished_deliveries_not_delivering = 0,

    overdue_items_removed = 0,
    overdue_intervals = 0,
    overdue_intervals_removed = 0,
  }
end

local function get_delivery_key(item_name, quality)
  local cache_key = item_name .. quality
  local key = delivery_keys[cache_key]
  if not key then
    key = cache_key
    delivery_keys[cache_key] = key
  end
  return key
end

local function get_interval_key(tick)
  -- Get the interval key for a given tick
  return math_floor(tick / INTERVAL_TICKS) * INTERVAL_TICKS
end

-- Add a completed delivery order to the history
local function add_delivered_order_to_history(delivery_history, order)
  local key = get_delivery_key(order.item_name, order.quality_name)
  if not delivery_history[key] then
    -- It's the first time this item has been delivered
    delivery_history[key] = {
      item_name = order.item_name,
      quality_name = order.quality_name,
      count = 0,
      ticks = 0,
    }
  end

  local history_order = delivery_history[key]
  local order_count = order.count
  history_order.count = (history_order.count or 0) + order_count

  local ticks = order.last_seen - order.first_seen
  if ticks < 1 then ticks = 1 end

  -- Update history stats
  history_order.ticks = (history_order.ticks or 0) + ticks
  history_order.avg = history_order.ticks / history_order.count
end

-- Process all bots expected to arrive in this interval
local function process_history_interval(interval_deliveries, tick_margin)
  -- Cache global access
  local delivery_history = storage.delivery_history
  local current_tick = game.tick

  local expired_bots = {}
  local count_to_remove = 0

  mystats.history_intervals = mystats.history_intervals + 1
  mystats.history_interval_items = mystats.history_interval_items + table_size(interval_deliveries)

  -- First pass: collect keys to remove and process history updates
  for unit_number, order in pairs(interval_deliveries) do
    if order.last_seen < current_tick - tick_margin then
      -- Use get_delivery_key for consistent string interning
      mystats.history_interval_ok = mystats.history_interval_ok + 1

      add_delivered_order_to_history(delivery_history, order)
      -- Mark for removal
      count_to_remove = count_to_remove + 1
      expired_bots[count_to_remove] = unit_number
    else
      mystats.history_interval_notyet = mystats.history_interval_notyet + 1
    end
  end

  -- Second pass: remove expired entries
  for i = 1, count_to_remove do
    local unit_number = expired_bots[i]
    interval_deliveries[unit_number] = nil

    -- Also clean up the lookup table
    if storage.bot_delivery_lookup then
      storage.bot_delivery_lookup[unit_number] = nil
    end
  end

  -- Return whether the interval is now empty and how many items were removed
  return next(interval_deliveries) == nil, count_to_remove
end

-- Process all deliveries in intervals earlier than the current one
local function process_overdue_deliveries(bot_active_deliveries, current_interval, tick_margin)
  local intervals_to_remove = {}
  local processed_count = 0

  -- Find all keys less than current_interval
  for interval_key, interval_deliveries in pairs(bot_active_deliveries) do
    if interval_key < current_interval then
      mystats.overdue_intervals = mystats.overdue_intervals + 1
      -- Process this interval
      local is_empty, removed_count = process_history_interval(interval_deliveries, tick_margin)
      processed_count = processed_count + removed_count

      -- If interval is now empty, mark it for removal
      if is_empty then
         mystats.overdue_intervals_removed = mystats.overdue_intervals_removed + 1
        table.insert(intervals_to_remove, interval_key)
      end
    end
  end

  if processed_count == 0 and #intervals_to_remove == 0 then
    return 0
  end

  -- Clean up empty intervals
  for _, interval_key in ipairs(intervals_to_remove) do
    bot_active_deliveries[interval_key] = nil
  end

  mystats.overdue_items_removed = mystats.overdue_items_removed + processed_count
  return processed_count
end

local function manage_active_deliveries_history(tick_margin)
  -- This function is called to manage the history of active deliveries
  -- It will remove entries that are no longer active and update the history
  local bot_active_deliveries = storage.bot_active_deliveries
  if bot_active_deliveries == nil then
    bot_active_deliveries = {}
    storage.bot_active_deliveries = bot_active_deliveries
  end

  -- Process only the current interval
  local current_tick = game.tick
  local current_interval = get_interval_key(current_tick)
  local interval_deliveries = bot_active_deliveries[current_interval]

  -- Process the current interval if it exists
  if interval_deliveries then
    local is_empty, removed_count = process_history_interval(interval_deliveries, tick_margin)

    -- Clean up empty interval if needed
    if is_empty and removed_count > 0 then
      bot_active_deliveries[current_interval] = nil
    end
  end

  -- Process any deliveries in earlier intervals that might be overdue
  process_overdue_deliveries(bot_active_deliveries, current_interval, tick_margin)
end

-- Counting bots in chunks
local function bot_initialise(partial_data)
  partial_data.delivering_bots = 0
  partial_data.picking_bots = 0
  partial_data.item_deliveries = {} -- Reset deliveries for this chunk
end

-- Estimate how many ticks it will take to charge from bot_energy to max_energy at cell
local function estimate_charge_ticks(cell, bot_energy, max_energy)
  local roboport = cell.owner
  local charge_energy = roboport.prototype.logistic_parameters.charging_energy
  local roboport_quality = roboport.quality
  if roboport_quality then
    charge_energy = charge_energy * roboport_quality.logistic_cell_charging_energy_multiplier
  end

  -- Calculate how many ticks it will take to charge the bot
  return math_ceil((max_energy - bot_energy) / charge_energy)
end

-- Estimate on which tick the delivery will happen
-- Returns the estimated tick, and whether the bot is likely to need to charge on the way
local function estimated_delivery_ticks(bot, order)
  if not bot or not bot.valid or not order or not order.target or not order.target.valid then
    return nil
  end

  if cached_logistic_bot_speed == nil then
    cached_logistic_bot_speed = bot.prototype.speed * (1 + bot.force.worker_robots_speed_modifier)
  end

  local buffer = 0
  local distance = utils.distance(bot.position, order.target.position)

  -- Check if it's likely to run out of charge before getting there
  local energy_needed_for_distance = bot.prototype.energy_per_move * distance
  local max_energy = bot.prototype.get_max_energy()
  local bot_quality = bot.quality
  if bot_quality then
    max_energy = max_energy * bot_quality.flying_robot_max_energy_multiplier
  end
  local end_charge = (bot.energy - energy_needed_for_distance) / max_energy
  local needs_charging = end_charge < bot.prototype.min_to_charge
  local ischarging = false

  cell = bot.logistic_network.find_cell_closest_to(bot.position)
  if cell and cell.valid and (cell.charging_robot_count+cell.to_charge_robot_count > 0) then
    for _, cell_bot in pairs(cell.charging_robots) do
      if cell_bot.unit_number == bot.unit_number then
        -- The bot is charging!
        buffer = estimate_charge_ticks(cell, bot.energy, max_energy)
        ischarging = true
        break
      end
    end
    if not ischarging then
      for _, cell_bot in pairs(cell.to_charge_robots) do
        if cell_bot.unit_number == bot.unit_number then
          -- The bot is waiting to charge!
          buffer = 10 + estimate_charge_ticks(cell, bot.energy, max_energy)
          ischarging = true
          break
        end
      end
    end
  end

  if needs_charging then
    if ischarging then
      -- It's currently charging, to see if it still needs a recharge when it's full.
      end_charge = (max_energy - energy_needed_for_distance) / max_energy
      if end_charge < bot.prototype.min_to_charge then
        -- Add a full charge
        buffer = buffer + estimate_charge_ticks(cell, 0, max_energy)
      end

    end
  end

  return buffer + math_ceil(distance / cached_logistic_bot_speed), needs_charging
end

-- Keep track of how many items of each type is being delivered right now
local function add_item_to_current_deliveries(item_name, quality, count, partial_data)
  local key = get_delivery_key(item_name, quality)
  if partial_data.item_deliveries[key] == nil then
    -- Order not seen before
    partial_data.item_deliveries[key] = {
      item_name = item_name,
      quality_name = quality,
      count = count,
    }
  else -- This item is already being delivered by another bot
    partial_data.item_deliveries[key].count = partial_data.item_deliveries[key].count + count
  end
end

-- This function adds to the list of things being delivered for the purpose of calculating history
local function add_bot_to_active_deliveries(bot, order, item_name, quality, count)
  if not bot.valid or not order then
    return
  end

  local current_tick = game.tick
  local unit_number = bot.unit_number

  -- Check if this bot is already being tracked somewhere
  local existing_interval = storage.bot_delivery_lookup[unit_number]
  if existing_interval then
    -- Bot is already tracked, just update last_seen time
    if storage.bot_active_deliveries[existing_interval] then
      local botorder = storage.bot_active_deliveries[existing_interval][unit_number]
      if botorder then
        if botorder.estimated_delivery_tick > current_tick then
          return -- Don't do anything until it's meant to arrive
        end
        -- if botorder.needs_charging then
        --   -- It's late because it needs to charge. Estimate new arrival time
        --   local estimate1, needs = estimated_delivery_ticks(bot, order)
        --   estimated_delivery_tick = current_tick + estimate1

        --   --botorder.needs_charging = needs
        --   botorder.was_charged = not needs
        --   if not needs then
        --     mystats.was_charged = mystats.was_charged + 1
        --   end
        --   botorder.estimated_delivery_tick = current_tick + estimate1
        --   local interval_key = get_interval_key(estimated_delivery_tick)

        --   -- Remove it from the old interval, and add to the new one
        --   storage.bot_active_deliveries[existing_interval][unit_number] = nil
        --   storage.bot_delivery_lookup[unit_number] = interval_key
        --   if storage.bot_active_deliveries[interval_key] == nil then
        --     storage.bot_active_deliveries[interval_key] = {}
        --   end
        --   storage.bot_active_deliveries[interval_key][unit_number] = botorder
        -- end
        -- Debug: Test if delivery estimate drifts
        -- local estimate1, needs = estimated_delivery_ticks(bot, order)
        -- local estimated_delivery_tick1 = current_tick + estimate1
        -- if math.abs(botorder.estimated_delivery_tick - estimated_delivery_tick1) > 60 then
        --   if botorder.first_seen_at.x == bot.position.x and botorder.first_seen_at.y == bot.position.y then
        --     mystats.stationary_mystery = mystats.stationary_mystery + 1
        --   end
        --   mystats.estimate_drifts = mystats.estimate_drifts + 1
        -- end

        -- if botorder.estimated_delivery_tick+60 < current_tick and not botorder.is_late then
        --   -- Debug
        --   local player_table = player_data.get_singleplayer_table()
        --   local bots = player_table.network.logistic_robots
        --   botorder.is_late = true
        --   mystats.late_bots = mystats.late_bots + 1
        -- end
        botorder.last_seen = current_tick
        return
      else
        -- The bot is not in that interval anymore, remove it from the lookup
        storage.bot_delivery_lookup[unit_number] = nil
      end
    else
      -- The lookup is stale, the bot isn't actually in that interval anymore
      storage.bot_delivery_lookup[unit_number] = nil
    end
  end

  -- If we got here, the bot isn't being tracked or has a stale lookup
  -- Calculate estimate and delivery interval
  local estimate, needs_charging = estimated_delivery_ticks(bot, order)
  local estimated_delivery_tick = current_tick + estimate

  -- Calculate the interval this delivery belongs to
  local interval_key = get_interval_key(estimated_delivery_tick)

  -- Ensure interval exists
  if storage.bot_active_deliveries[interval_key] == nil then
    storage.bot_active_deliveries[interval_key] = {}
  end

  -- Add the bot to the tracking system
  storage.bot_active_deliveries[interval_key][unit_number] = {
    item_name = item_name,
    quality_name = quality,
    count = count,
    first_seen = current_tick,
    last_seen = current_tick,
    estimated_ticks = estimate,
    estimated_delivery_tick = estimated_delivery_tick,
    start_energy = bot.energy,
    first_seen_at = bot.position,
    targetpos = order.target.position,
    order = order,
    needs_charging = needs_charging,
    was_charged = false,
  }

  -- Update the lookup table
  storage.bot_delivery_lookup[unit_number] = interval_key
end

-- Check if the bot has finished its delivery and update the history accordingly
local function check_if_no_order_bot_finished_delivery(bot)
  local finished = false
  local unit_number = bot.unit_number
  interval = storage.bot_delivery_lookup[unit_number]
  if interval then
    -- The bot has a delivery interval but no delivery, so it's finished
    local delivered_order = storage.bot_active_deliveries[interval][unit_number]
    add_delivered_order_to_history(storage.delivery_history, delivered_order)

    -- Remove from active deliveries being tracked
    storage.bot_delivery_lookup[unit_number] = nil
    storage.bot_active_deliveries[interval][unit_number] = nil
    finished = true
  end
  return finished
end

-- This function is called by the chunker once for every bot in the list
local function process_one_bot(bot, accumulator, player_table)
  if bot and bot.valid then
    if table_size(bot.robot_order_queue) > 0 then
      local order = bot.robot_order_queue[1]
      if order.type == defines_robot_order_type_deliver then
        accumulator.delivering_bots = accumulator.delivering_bots + 1
      elseif order.type == defines_robot_order_type_pickup then
        accumulator.picking_bots = accumulator.picking_bots + 1
      end

      local item_name = order.target_item.name.name
      -- For Deliveries, record the item
      if order.type == defines_robot_order_type_deliver and item_name then
        local item_count = order.target_count
        local quality = order.target_item.quality.name
        -- Record current deliveries
        add_item_to_current_deliveries(item_name, quality, item_count, accumulator)
        if player_table.settings.show_history then
          -- Record delivery for history purposes
          add_bot_to_active_deliveries(bot, order, item_name, quality, item_count)
        end
      else
        -- Check if the bot was delivering last time we saw it, and record the delivery
        if player_table.settings.show_history then
          if check_if_no_order_bot_finished_delivery(bot) then
            mystats.finished_deliveries_not_delivering = mystats.finished_deliveries_not_delivering + 1
          end
        end
      end
    else
      -- No orders, check if it's because the bot has finished its delivery
      if player_table.settings.show_history then
        -- Only do this if we're collecting history as the partial data is only used for one pass
        if check_if_no_order_bot_finished_delivery(bot) then
          mystats.finished_deliveries_no_order = mystats.finished_deliveries_no_order + 1
        end
      end
    end
  end
end

-- This function is called when all chunks are done processing, ready for a new chunk
local function bot_chunks_done(data)
  storage.bot_items["delivering"] = data.delivering_bots
  storage.bot_items["picking"] = data.picking_bots
  storage.bot_deliveries = data.item_deliveries or {}
end

-- Use the generic chunker to process bots in chunks for performance reasons
local bot_chunker = chunker.new(bot_initialise, process_one_bot, bot_chunks_done)


-- When the network changes, reset all bot data
function bot_counter.network_changed(player, player_table)
  -- Clear all current state when we change networks
  bot_chunker:reset()
  storage.bot_items = storage.bot_items or {}
  storage.delivery_history = {}
  storage.bot_active_deliveries = {}
  storage.bot_delivery_lookup = {}
  clear_mystats()
end

-- Gather bot delivery data for all bots, one chunk at a time, then curate history
function bot_counter.gather_bot_data(player, player_table)
  local network = player_table.network
  local progress = { current = 0, total = 0 }

  if not network or not network.valid or player_data.is_paused(player_table) then
    return progress
  end
  local show_delivering = player_table.settings.show_delivering
  local show_history = player_table.settings.show_history
  if mystats == nil then
    clear_mystats()
  end

  if show_delivering or show_history then
    if bot_chunker:is_done() then
      --clear_mystats()
      bot_chunker:initialise_chunking(network.logistic_robots, player_table)
    end
    bot_chunker:process_chunk()
    progress = bot_chunker:get_progress()
  else
    storage.bot_items["delivering"] = nil
    storage.bot_items["picking"] = nil
  end

  -- Update delivery history
  if show_history then
    local tick_margin = math_max(0, bot_chunker:num_chunks() * player_data.bot_chunk_interval(player_table) - 1)
    cached_logistic_bot_speed = nil -- Reset cached speed to ensure it's recalculated
    manage_active_deliveries_history(tick_margin)
  end

  return progress
end

return bot_counter
