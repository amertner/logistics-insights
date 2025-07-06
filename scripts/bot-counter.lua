bot_counter = {}

local player_data = require("scripts.player-data")
local chunker = require("scripts.chunker")

local function manage_active_deliveries_history()
  -- This function is called to manage the history of active deliveries
  -- It will remove entries that are no longer active and update the history
  if storage.bot_active_deliveries == nil then
    storage.bot_active_deliveries = {}
  end

  for unit_number, order in pairs(storage.bot_active_deliveries) do
     -- TODO This is a bit nasty, improve if we allow users to choose tick rate of updates
    if order.last_seen < game.tick-50 then
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

-- Counting network cells in chunks
local function network_initialise(partial_data)
  partial_data.bots_charging = 0
  partial_data.bots_waiting_for_charge = 0
end

local function network_processing(entity, partial_data, player_table)
  partial_data.bots_charging = partial_data.bots_charging + entity.charging_robot_count
  partial_data.bots_waiting_for_charge = partial_data.bots_waiting_for_charge + entity.to_charge_robot_count
end

local function network_chunks_done(data)
  storage.bot_items["charging-robot"] = data.bots_charging
  storage.bot_items["waiting-for-charge-robot"] = data.bots_waiting_for_charge
end

local activity_chunker = chunker.new(network_initialise, network_processing, network_chunks_done)


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
  storage.bot_items["delivering"] = data.delivering_bots or 0
  storage.bot_items["picking"] = data.picking_bots or 0
  storage.bot_deliveries = data.item_deliveries or {}
end

local bot_chunker = chunker.new(bot_initialise, bot_processing, bot_chunks_done)


-- Main counting function, called periodically
function bot_counter.gather_data(game)
  local player = player_data.get_singleplayer_player()
  local player_table = player_data.get_singleplayer_table()

  local network = player.force.find_logistic_network_by_position(player.position, player.surface)
  if not player_table.network or not player_table.network.valid or not network or
      player_table.network.network_id ~= network.network_id then
    -- Clear all current state when we change networks
    activity_chunker:reset()
    bot_chunker:reset()
    storage.bot_items = {}
    storage.delivery_history = {}
    storage.bot_active_deliveries = {}
    player_table.network = network
  end

  if network then
    storage.bot_items["logistic-robot-total"] = network.all_logistic_robots
    storage.bot_items["logistic-robot-available"] = network.available_logistic_robots
    if activity_chunker:is_done() then
      activity_chunker:initialise_chunking(network.cells)
    end
    activity_chunker:process_chunk()

    if not player_table.paused then -- These are the expensive ones, so only do them when not paused
      if player_table.settings.show_delivering or player_table.settings.show_history then
        if bot_chunker:is_done() then
          bot_chunker:initialise_chunking(network.logistic_robots)
        end
        bot_chunker:process_chunk()
      end

      -- Find orders that have been delivered add to history
      if player_table.settings.show_history then
        manage_active_deliveries_history()
      end
    end
  end -- if network

  return {
    activity_progress = activity_chunker:get_progress(),
    bot_progress = bot_chunker:get_progress(),
  }
end

return bot_counter
