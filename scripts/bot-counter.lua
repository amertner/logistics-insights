local bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")
local utils = require("scripts.utils")
local analysis = require("scripts.analysis")

-- Cache frequently used functions and values for performance
local pairs = pairs
local table_size = table_size
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup
local seen_bot_this_pass = 2
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

-- Create a table to store combined (name/quality) keys for reduced memory fragmentation
local delivery_keys = {}

--- Get a cached delivery key for item name and quality combination
--- @param item_name string The name of the item
--- @param quality string The quality name (e.g., "normal", "uncommon", etc.)
--- @return string The cached delivery key
local function get_delivery_key(item_name, quality)
  local cache_key = item_name .. quality
  local key = delivery_keys[cache_key]
  if not key then
    key = cache_key
    delivery_keys[cache_key] = key
  end
  return key
end

--- Add a completed delivery order to the history storage
--- @param delivery_history table<string, DeliveredItems> The delivery history storage table
--- @param order BotDeliveringInFlight The completed order
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
      avg = 0,
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

--- Keep track of how many items of each type is being delivered right now
--- @param item_name string The name of the item being delivered
--- @param localised_name LocalisedString The localised display name of the item
--- @param quality string The quality name of the item
--- @param localised_quality_name LocalisedString The localised display name of the quality
--- @param count number The number of items being delivered
--- @param item_deliveries table<string, DeliveryItem> The list of current deliveries
local function add_item_to_current_deliveries(item_name, localised_name, quality, localised_quality_name, count, item_deliveries)
  local key = get_delivery_key(item_name, quality)
  if item_deliveries[key] == nil then
    -- Order not seen before
    item_deliveries[key] = {
      item_name = item_name,
      quality_name = quality,
      localised_name = localised_name,
      localised_quality_name = localised_quality_name,
      count = count,
    }
  else -- This item is already being delivered by another bot
    item_deliveries[key].count = item_deliveries[key].count + count
  end
end

--- Add the bot and order to the list of things being delivered for the purpose of calculating history
--- @param bot LuaEntity The robot entity
--- @param order table The robot's delivery order
--- @param item_name string The name of the item being delivered
--- @param localised_name LocalisedString The localised display name of the item
--- @param quality string The quality name of the item
--- @param localised_quality_name LocalisedString The localised display name of the quality
--- @param count number The number of items being delivered
local function add_bot_to_active_deliveries(bot, order, item_name, localised_name, quality, localised_quality_name, count)
  if not bot.valid or not order then
    return
  end
  local current_tick = game.tick
  local unit_number = bot.unit_number
  if not unit_number then
    -- No unit number, so we can't track this bot
    return
  end
  local botorder = storage.bot_active_deliveries[unit_number]

  if botorder then
    -- We have an existing order for this bot
    if botorder.targetpos and order.target and order.target.position and
       (botorder.targetpos.x ~= order.target.position.x or
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
      targetpos = order.target and order.target.position,
    }
  end
end

--- The bot is not delivering an order; check if the bot finished a prior delivery
--- and update the history accordingly
--- @param unit_number number The unique identifier of the robot
--- @param show_history boolean Whether history tracking is enabled
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

--- This function is called by the chunker once for every bot in the list
--- @param bot LuaEntity The robot entity to process
--- @param accumulator Accumulator The data accumulator containing counters and bot lists
--- @param player_table PlayerData The player's data table containing settings
local function process_one_bot(bot, accumulator, player_table)
  if bot and bot.valid then
    local unit_number = bot.unit_number
    if not unit_number then
      -- No unit number, so we can't track this bot
      return
    end
    if accumulator.last_seen[unit_number] then
      -- Mark bots seen in the last pass as seen again
      accumulator.last_seen[unit_number] = seen_bot_this_pass
    else
      -- Mark this bot as seen for the first time
      accumulator.just_seen[unit_number] = seen_bot_last_pass
    end
    -- Track the bot's quality
    local quality = (bot.quality and bot.quality.name) or "normal"

    local order = bot.robot_order_queue[1] or nil
    if order then
      if order and order.type == defines_robot_order_type_deliver then
        accumulator.delivering_bots = accumulator.delivering_bots + 1
        utils.accumulate_quality(accumulator.delivering_bot_qualities, quality, 1)
      elseif order and order.type == defines_robot_order_type_pickup then
        accumulator.picking_bots = accumulator.picking_bots + 1
        utils.accumulate_quality(accumulator.picking_bot_qualities, quality, 1)
      end

      if order.target_item and order.target_item.name then
        local targetname = order.target_item.name
        local item_name = targetname.name
        -- For Deliveries, record the item
        if order.type == defines_robot_order_type_deliver and item_name then
          local item_count = order.target_count or 0
          local item_quality = order.target_item.quality and order.target_item.quality.name or "normal"
          local localised_name = targetname.localised_name
          local localised_quality_name = order.target_item.quality and order.target_item.quality.localised_name or ""

          -- Record current deliveries
          add_item_to_current_deliveries(item_name, localised_name, item_quality, localised_quality_name, item_count, accumulator.item_deliveries)
          -- Record delivery for history purposes
          add_bot_to_active_deliveries(bot, order, item_name, localised_name, item_quality, localised_quality_name, item_count)
        else
          -- Check if the bot was delivering last time we saw it, and record the delivery
          check_if_no_order_bot_finished_delivery(unit_number, player_table.settings.show_history)
        end
      else
        -- This is a situation that should not occur: we haver an order but no target item. Clear it.
        check_if_no_order_bot_finished_delivery(unit_number, player_table.settings.show_history)
      end
    else
      -- No orders, check if it's because the bot has finished its delivery
      check_if_no_order_bot_finished_delivery(unit_number, player_table.settings.show_history)
      utils.accumulate_quality(accumulator.other_bot_qualities, quality, 1)
    end
  end
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
end

--- This function is called when all chunks are done processing, ready for a new chunk
--- @param accumulator Accumulator The data accumulator containing all gathered statistics
--- @param player_table PlayerData The player's data table containing settings
local function bot_chunks_done(accumulator, player_table)
  storage.bot_items["delivering"] = accumulator.delivering_bots or nil
  storage.bot_items["picking"] = accumulator.picking_bots or nil
  storage.bot_deliveries = accumulator.item_deliveries or {}
  storage.delivering_bot_qualities = accumulator.delivering_bot_qualities or {}
  storage.picking_bot_qualities = accumulator.picking_bot_qualities or {}
  storage.other_bot_qualities = accumulator.other_bot_qualities or {}
    -- Sum all of the qualities gathered by bot-counter, plus idle ones, to get the totals
  local total_bot_qualities = {}
  if prototypes and prototypes.quality and prototypes.quality.normal then
    local quality = prototypes.quality.normal
    while quality and quality.name do
      local qname = quality.name
      local amount = (storage.idle_bot_qualities[qname] or 0)
        + (storage.picking_bot_qualities[qname] or 0)
        + (storage.delivering_bot_qualities[qname] or 0)
        + (storage.other_bot_qualities[qname] or 0)
      total_bot_qualities[qname] = amount
      -- Go to the next higher quality
      quality = quality.next
    end
  end
  storage.total_bot_qualities = total_bot_qualities

  if player_table and player_table.settings.show_history and table_size(storage.bot_active_deliveries) > 0 then
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

  -- See if there are new suggestions based on the data just gathered
  if player_table and player_table.suggestions and not player_data.is_suggestions_paused(player_table) then
    player_table.suggestions:bots_data_updated(player_table.network)
  end
  -- Analyse demand and supply based on the gathered data, unless paused
  if player_table and not player_data.is_undersupply_paused(player_table) then
    analysis:analyse_demand_and_supply(player_table.network)
  end
end

-- Use the generic chunker to process bots in chunks, to moderate CPU usage
local bot_chunker = chunker.new(bot_initialise_chunking, process_one_bot, bot_chunks_done)

--- Process data gathered so far and start over
function bot_counter.restart_counting()
  bot_chunker:reset()
end

--- When the network changes, reset all bot data
--- @param player LuaPlayer|nil The player whose network changed
--- @param player_table PlayerData|nil The player's data table
function bot_counter.network_changed(player, player_table)
  -- Clear all current state when we change networks
  bot_chunker:reset()
  player_data.init_bot_counter_storage()
end

--- Gather bot delivery data for all bots, one chunk at a time
--- @param player? LuaPlayer The player to gather bot data for
--- @param player_table? PlayerData The player's data table containing network and settings
--- @return Progress progress A table with current and total progress values
function bot_counter.gather_bot_data(player, player_table)
  local progress = { current = 0, total = 0 }
  if not player_table then
    return progress
  end

  local network = player_table.network
  if not network or not network.valid or player_data.is_history_paused(player_table) then
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
