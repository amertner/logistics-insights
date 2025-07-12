bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")
local activity_counter = require("scripts.activity-counter")

local function manage_active_deliveries_history(bot_chunker, tick_margin)
  -- This function is called to manage the history of active deliveries
  -- It will remove entries that are no longer active and update the history
  if storage.bot_active_deliveries == nil then
    storage.bot_active_deliveries = {}
  end

  for unit_number, order in pairs(storage.bot_active_deliveries) do
    if order.last_seen < game.tick-tick_margin then
      local key = order.item_name .. order.quality_name
      if storage.delivery_history[key] == nil then
        storage.delivery_history[key] = {
          item_name = order.item_name,
          quality_name = order.quality_name,
          count = 0,
          ticks = 0,
        }
      end
      local history_order = storage.delivery_history[key]
      history_order.count = (history_order.count or 0) + order.count
      local ticks = order.last_seen - order.first_seen
      if ticks < 1 then ticks = 1 end
      history_order.ticks = (history_order.ticks or 0) + ticks
      history_order.avg = history_order.ticks / history_order.count
      storage.bot_active_deliveries[unit_number] = nil -- remove from active list
    end
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
  key = item_name .. quality
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
    order = bot.robot_order_queue[1]
    if order.type == defines.robot_order_type.deliver then
      partial_data.delivering_bots = (partial_data.delivering_bots or 0) + 1
    elseif order.type == defines.robot_order_type.pickup then
      partial_data.picking_bots = (partial_data.picking_bots or 0) + 1
    end

    local item_name = order.target_item.name.name
    local item_count = order.target_count
    local quality = order.target_item.quality.name
    -- For Deliveries, record the item
    if order.type == defines.robot_order_type.deliver and item_name then
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
  
  -- Process robot delivery data if needed
  if player_table.settings.show_delivering or player_table.settings.show_history then
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
  if player_table.settings.show_history then
    tick_margin = math.max(0, bot_chunker:num_chunks() * player_data.bot_chunk_interval(player_table) - 1)
    manage_active_deliveries_history(bot_chunker, tick_margin)
  end
  
  return progress
end

return bot_counter
