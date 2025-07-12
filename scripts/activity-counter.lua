local activity_counter = {}

local player_data = require("scripts.player-data")

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

local activity_chunker = require("scripts.chunker").new(network_initialise, network_processing, network_chunks_done)

-- Get or update the network, return true if the network is valid and update player_table.network
local function update_network(player, player_table)
  local network = player.force.find_logistic_network_by_position(player.position, player.surface)
  
  if not player_table.network or not player_table.network.valid or not network or
      player_table.network.network_id ~= network.network_id then
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
  progress = { current = 0, total = 0 }
  if not update_network(player, player_table) then
    return progress
  end
  local network = player_table.network
  
  -- Store basic network stats
  storage.bot_items["logistic-robot-total"] = network.all_logistic_robots
  storage.bot_items["logistic-robot-available"] = network.available_logistic_robots
  
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
