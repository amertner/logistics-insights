local bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")
local activity_counter = require("scripts.activity-counter")

-- Cache frequently used functions and values for performance
local pairs = pairs
local table_size = table_size
local math_max = math.max
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup

-- Create a table to store combined keys for reduced memory fragmentation
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

local function manage_active_deliveries_history(tick_margin)
  -- This function is called to manage the history of active deliveries
  -- It will remove entries that are no longer active and update the history
  local bot_active_deliveries = storage.bot_active_deliveries
  if bot_active_deliveries == nil then
    bot_active_deliveries = {}
    storage.bot_active_deliveries = bot_active_deliveries
  end
  
  -- Cache global access
  local delivery_history = storage.delivery_history
  local current_tick = game.tick
  local expired_bots = {}
  local count_to_remove = 0
  
  -- First pass: collect keys to remove and process history updates
  for unit_number, order in pairs(bot_active_deliveries) do
    if order.last_seen < current_tick - tick_margin then
      -- Use get_delivery_key for consistent string interning
      local key = get_delivery_key(order.item_name, order.quality_name)
      if not delivery_history[key] then
        delivery_history[key] = {
          item_name = order.item_name,
          quality_name = order.quality_name,
          count = 0,
          ticks = 0,
        }
      end
      
      -- Update history with this completed delivery
      local history_order = delivery_history[key]
      local order_count = order.count
      history_order.count = (history_order.count or 0) + order_count
      
      local ticks = order.last_seen - order.first_seen
      if ticks < 1 then ticks = 1 end
      
      -- Update history stats
      history_order.ticks = (history_order.ticks or 0) + ticks
      history_order.avg = history_order.ticks / history_order.count
      
      -- Mark for removal
      count_to_remove = count_to_remove + 1
      expired_bots[count_to_remove] = unit_number
    end
  end
  
  -- Second pass: remove expired entries
  for i = 1, count_to_remove do
    bot_active_deliveries[expired_bots[i]] = nil
  end
end

-- Counting bots in chunks
local function bot_initialise(partial_data)
  partial_data.delivering_bots = 0
  partial_data.picking_bots = 0
  partial_data.item_deliveries = {} -- Reset deliveries for this chunk
end

-- Keep track of how many items of each type is being delivered right now
local function add_item_to_bot_deliveries(item_name, quality, count, partial_data)
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

local function add_bot_to_active_deliveries(bot, item_name, quality, count)
  if storage.bot_active_deliveries[bot.unit_number] == nil then
    -- Order not seen before
    storage.bot_active_deliveries[bot.unit_number] = {
      item_name = item_name,
      quality_name = quality,
      count = count,
      first_seen = game.tick,
      last_seen = game.tick,
    }
  else -- It's still under way
    storage.bot_active_deliveries[bot.unit_number].last_seen = game.tick
  end
end

local function bot_processing(bot, partial_data, player_table)
  if bot.valid and table_size(bot.robot_order_queue) > 0 then
    local order = bot.robot_order_queue[1]
    if order.type == defines_robot_order_type_deliver then
      partial_data.delivering_bots = (partial_data.delivering_bots or 0) + 1
    elseif order.type == defines_robot_order_type_pickup then
      partial_data.picking_bots = (partial_data.picking_bots or 0) + 1
    end

    local item_name = order.target_item.name.name
    local item_count = order.target_count
    local quality = order.target_item.quality.name
    -- For Deliveries, record the item
    if order.type == defines_robot_order_type_deliver and item_name then
      add_item_to_bot_deliveries(item_name, quality, item_count, partial_data)
      if player_table.settings.show_history then
        add_bot_to_active_deliveries(bot, item_name, quality, item_count)
      end
    end
  end
end

local function bot_chunks_done(data)
  storage.bot_items["delivering"] = data.delivering_bots or nil
  storage.bot_items["picking"] = data.picking_bots or nil
  storage.bot_deliveries = data.item_deliveries or {}
end

local bot_chunker = chunker.new(bot_initialise, bot_processing, bot_chunks_done)


-- Get or update the network, return true if the network is valid and update player_table.network
local function update_network(player, player_table)
  local network = player.force.find_logistic_network_by_position(player.position, player.surface)
  
  if not player_table.network or not player_table.network.valid or not network or
      player_table.network.network_id ~= network.network_id then
    -- Clear all current state when we change networks
    activity_counter.reset_chunker() -- Tell activity_counter to reset its chunker
    bot_chunker:reset()
    storage.bot_items = storage.bot_items or {}
    storage.delivery_history = {}
    storage.bot_active_deliveries = {}
    player_table.network = network
  end
  
  return network and network.valid
end

-- No longer need the forwarding function as control.lua now calls activity_counter directly

-- Gather bot delivery data
function bot_counter.gather_bot_data(player, player_table)
  -- First update and validate network
  if not update_network(player, player_table) then
    return { current = 0, total = 0 }
  end

  local network = player_table.network
  local progress = { current = 0, total = 0 }

  if player_data.is_paused(player_table) then
    return progress
  end
  local show_delivering = player_table.settings.show_delivering
  local show_history = player_table.settings.show_history

  -- Process robot delivery data if needed
  if show_delivering or show_history then
    if bot_chunker:is_done() then
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
    manage_active_deliveries_history(tick_margin)
  end

  return progress
end

return bot_counter
