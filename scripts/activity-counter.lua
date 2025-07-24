local activity_counter = {}

local player_data = require("scripts.player-data")

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

local function network_chunks_done(data, player_table)
  local bot_items = storage.bot_items
  bot_items["charging-robot"] = data.bots_charging
  bot_items["waiting-for-charge-robot"] = data.bots_waiting_for_charge
end

local activity_chunker = require("scripts.chunker").new(network_initialise, network_processing, network_chunks_done)

function activity_counter.network_changed(player, player_table)
  activity_chunker:reset()
end

-- Gather activity data (cells, charging robots, etc.)
function activity_counter.gather_data(player, player_table)
  -- First update and validate network
  local progress = { current = 0, total = 0 } -- Use local variable to avoid global access
  local network = player_table.network
  local bot_items = storage.bot_items       -- Cache the table lookup
  if not network or not network.valid then
    return progress
  end

  -- Store basic network stats
  bot_items["logistic-robot-total"] = network.all_logistic_robots
  bot_items["logistic-robot-available"] = network.available_logistic_robots

  if player_data.is_paused(player_table) then
    return progress
  end

  -- Process cell data
  if activity_chunker:is_done() then
    activity_chunker:initialise_chunking(network.cells, player_table, nil)
    player_data.set_activity_chunks(player_table, activity_chunker:num_chunks())
  end
  activity_chunker:process_chunk()

  return activity_chunker:get_progress()
end

return activity_counter
