local activity_counter = {}

local player_data = require("scripts.player-data")

-- Cache frequently used functions for performance
local pairs = pairs
local math_max = math.max
local math_ceil = math.ceil

-- Counting network cells in chunks
local function network_initialise(partial_data)
  partial_data.bots_charging = 0
  partial_data.bots_waiting_for_charge = 0
end

local function network_processing(entity, partial_data, player_table)
  local bots_charging = partial_data.bots_charging
  local bots_waiting = partial_data.bots_waiting_for_charge
  
  partial_data.bots_charging = bots_charging + entity.charging_robot_count
  partial_data.bots_waiting_for_charge = bots_waiting + entity.to_charge_robot_count
end

local function network_chunks_done(data)
  local bot_items = storage.bot_items
  bot_items["charging-robot"] = data.bots_charging
  bot_items["waiting-for-charge-robot"] = data.bots_waiting_for_charge
end

local activity_chunker = require("scripts.chunker").new(network_initialise, network_processing, network_chunks_done)

-- Get or update the network, return true if the network is valid and update player_table.network
local function update_network(player, player_table)
  local network = player.force.find_logistic_network_by_position(player.position, player.surface)
  local current_network = player_table.network
  
  if not current_network or not current_network.valid or not network or
      current_network.network_id ~= network.network_id then
    -- Clear activity state when we change networks
    activity_chunker:reset()
    storage.bot_items = storage.bot_items or {}
    player_table.network = network
  end
  
  return network and network.valid
end

-- Reset chunker state (called from bot-counter when network changes)
function activity_counter.reset_chunker()
  activity_chunker:reset()
end

-- Gather activity data (cells, charging robots, etc.)
function activity_counter.gather_data(player, player_table)
  -- First update and validate network
  local progress = { current = 0, total = 0 }  -- Use local variable to avoid global access
  if not update_network(player, player_table) then
    return progress
  end
  local network = player_table.network
  local bot_items = storage.bot_items  -- Cache the table lookup
  
  -- Store basic network stats
  bot_items["logistic-robot-total"] = network.all_logistic_robots
  bot_items["logistic-robot-available"] = network.available_logistic_robots
  
  if player_data.is_paused(player_table) then
    return progress
  end

  -- Process cell data
  if activity_chunker:is_done() then
    activity_chunker:initialise_chunking(network.cells, player_table)
    player_data.set_activity_chunks(player_table, activity_chunker:num_chunks())
  end
  activity_chunker:process_chunk()
  
  return activity_chunker:get_progress()
end

return activity_counter
