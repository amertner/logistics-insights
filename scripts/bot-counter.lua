local bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")

-- Cache frequently used functions and values for performance
local pairs = pairs
local table_size = table_size
local math_max = math.max
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup
local seen_bot_this_pass = 2
local seen_bot_last_pass = 1

-- Key storage structures:
--   bot_active_deliveries: Tracks orders currently being delivered, indexed by bot
--   delivery_history: Stores completed deliveries with their statistics, indxed by item+quality

-- Create a table to store combined (name/quality) keys for reduced memory fragmentation
local delivery_keys = {}

local function get_delivery_key(item_name, quality)
  local cache_key = item_name .. quality
  local key = delivery_keys[cache_key]
  if not key then
    key = cache_key
    delivery_keys[cache_key] = key
  end
  return key
end

-- Add a completed delivery order to the history
local function add_delivered_order_to_history(delivery_history, order)
  local key = get_delivery_key(order.item_name, order.quality_name)
  if not delivery_history[key] then
    -- It's the first time this item has been delivered
    delivery_history[key] = {
      item_name = order.item_name,
      quality_name = order.quality_name,
      localised_name = order.localised_name,
      localised_quality_name = order.localised_quality_name,
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

-- Keep track of how many items of each type is being delivered right now
local function add_item_to_current_deliveries(item_name, localised_name, quality, localised_quality_name, count, partial_data)
  local key = get_delivery_key(item_name, quality)
  if partial_data.item_deliveries[key] == nil then
    -- Order not seen before
    partial_data.item_deliveries[key] = {
      item_name = item_name,
      quality_name = quality,
      localised_name = localised_name,
      localised_quality_name = localised_quality_name,
      count = count,
    }
  else -- This item is already being delivered by another bot
    partial_data.item_deliveries[key].count = partial_data.item_deliveries[key].count + count
  end
end

-- Add the bot and order to the list of things being delivered for the purpose of calculating history
local function add_bot_to_active_deliveries(bot, order, item_name, localised_name, quality, localised_quality_name, count)
  if not bot.valid or not order then
    return
  end
  local current_tick = game.tick
  local unit_number = bot.unit_number
  local botorder = storage.bot_active_deliveries[unit_number]

  if botorder then
    -- We have an existing order for this bot
    if botorder.targetpos and (botorder.targetpos.x ~= order.target.position.x or
        botorder.targetpos.y ~= order.target.position.y) then
      -- New target position, so order has changed since last time
      add_delivered_order_to_history(storage.delivery_history, botorder)
      storage.bot_active_deliveries[unit_number] = nil
    else
      -- Just note that we've seen this order again
      botorder.last_seen = current_tick
    end
  else
    -- No order for this bot, so add it
    storage.bot_active_deliveries[unit_number] = {
      item_name = item_name,
      localised_name = localised_name,
      quality_name = quality,
      localised_quality_name = localised_quality_name,
      count = count,
      first_seen = current_tick,
      last_seen = current_tick,
      targetpos = order.target.position,
    }
  end
end

-- The bot is not delivering an order; check if the bot finished a prior delivery
-- and update the history accordingly
local function check_if_no_order_bot_finished_delivery(unit_number, show_history)
  if show_history then
    -- The bot has a delivery interval but no delivery, so it's finished
    local delivered_order = storage.bot_active_deliveries[unit_number]
    if delivered_order then
      add_delivered_order_to_history(storage.delivery_history, delivered_order)

      -- Remove from active deliveries being tracked
      storage.bot_active_deliveries[unit_number] = nil
    end
  end
end

-- This function is called by the chunker once for every bot in the list
local function process_one_bot(bot, accumulator, player_table)
  if bot and bot.valid then
    local unit_number = bot.unit_number
    if accumulator.last_seen[unit_number] then
      -- Mark bots seen in the last pass as seen again
      accumulator.last_seen[unit_number] = seen_bot_last_pass
    else
      -- Mark this bot as seen for the first time
      accumulator.just_seen[unit_number] = seen_bot_this_pass
    end

    if table_size(bot.robot_order_queue) > 0 then
      local order = bot.robot_order_queue[1]
      if order.type == defines_robot_order_type_deliver then
        accumulator.delivering_bots = accumulator.delivering_bots + 1
      elseif order.type == defines_robot_order_type_pickup then
        accumulator.picking_bots = accumulator.picking_bots + 1
      end

      local targetname = order.target_item.name
      local item_name = targetname.name
      -- For Deliveries, record the item
      if order.type == defines_robot_order_type_deliver and item_name then
        local item_count = order.target_count
        local quality = order.target_item.quality.name
        local localised_name = targetname.localised_name
        local localised_quality_name = order.target_item.quality.localised_name
      
        -- Record current deliveries
        add_item_to_current_deliveries(item_name, localised_name, quality, localised_quality_name, item_count, accumulator)
        -- Record delivery for history purposes
        add_bot_to_active_deliveries(bot, order, item_name, localised_name, quality, localised_quality_name, item_count)
      else
        -- Check if the bot was delivering last time we saw it, and record the delivery
        check_if_no_order_bot_finished_delivery(unit_number, player_table.settings.show_history)
      end
    else
      -- No orders, check if it's because the bot has finished its delivery
      check_if_no_order_bot_finished_delivery(unit_number, player_table.settings.show_history)
    end
  end
end

-- Reset counters to be able to process a list of data in chunks
local function bot_initialise_chunking(accumulator, last_seen)
  accumulator.delivering_bots = 0
  accumulator.picking_bots = 0
  accumulator.item_deliveries = {} -- Reset deliveries
  accumulator.last_seen = last_seen or {} -- The list of bots seen in the last pass
  accumulator.just_seen = {} -- The list of bots first seen this pass
end

-- This function is called when all chunks are done processing, ready for a new chunk
local function bot_chunks_done(accumulator, player_table)
  storage.bot_items["delivering"] = accumulator.delivering_bots or nil
  storage.bot_items["picking"] = accumulator.picking_bots or nil
  storage.bot_deliveries = accumulator.item_deliveries or {}

  if player_table.settings.show_history and table_size(storage.bot_active_deliveries) > 0 then
    -- Consider bots we saw last pass but not this chunk pass as delivered.
    -- They are either destroyed or parked in a roboport, no longer part of the network
    if accumulator.last_seen then
      for unit_number, seen in pairs(accumulator.last_seen) do
        if seen == seen_bot_this_pass then
          -- We saw this bot in the last pass
          accumulator.just_seen[unit_number] = seen_bot_last_pass
        else
          -- We did not see this bot in the last pass, so it probably finished its delivery
          check_if_no_order_bot_finished_delivery(unit_number, true)
        end
      end
    end
  end
  -- Save the last-seen list so it can be used in the next pass
  storage.last_pass_bots_seen = accumulator.just_seen or {}
end

-- Use the generic chunker to process bots in chunks, to moderate CPU usage
local bot_chunker = chunker.new(bot_initialise_chunking, process_one_bot, bot_chunks_done)

-- When the network changes, reset all bot data
function bot_counter.network_changed(player, player_table)
  -- Clear all current state when we change networks
  bot_chunker:reset()
  storage.bot_items = storage.bot_items or {}
  storage.delivery_history = {}
  storage.bot_active_deliveries = {}
  storage.last_pass_bots_seen = {}
end

-- Gather bot delivery data for all bots, one chunk at a time
function bot_counter.gather_bot_data(player, player_table)
  local network = player_table.network
  local progress = { current = 0, total = 0 }

  if not network or not network.valid or player_data.is_paused(player_table) then
    return progress
  end
  local show_delivering = player_table.settings.show_delivering
  local show_history = player_table.settings.show_history

  if show_delivering or show_history then
    if bot_chunker:is_done() then
      bot_chunker:initialise_chunking(network.logistic_robots, player_table, storage.last_pass_bots_seen)
    end
    bot_chunker:process_chunk()
    progress = bot_chunker:get_progress()
  else
    storage.bot_items["delivering"] = nil
    storage.bot_items["picking"] = nil
  end

  return progress
end

return bot_counter
