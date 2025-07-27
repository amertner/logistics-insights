local activity_counter = {}

local player_data = require("scripts.player-data")

-- Counting network cells in chunks
local function network_initialise(accumulator)
  accumulator.bots_charging = 0
  accumulator.bots_waiting_for_charge = 0
  accumulator.idle_bot_qualities = {} -- Gather quality of idle bots
  accumulator.roboport_qualities = {} -- Gather quality of roboports
  accumulator.charging_bot_qualities = {} -- Gather quality of charging bots
  accumulator.waiting_bot_qualities = {} -- Gather quality of bots waiting to charge
end

local function accumulate_quality(quality_table, quality, count)
  if not quality_table[quality] then
    quality_table[quality] = 0
  end
  quality_table[quality] = quality_table[quality] + count
end

local function process_one_cell(cell, accumulator, player_table)
  local bots_charging = accumulator.bots_charging
  local bots_waiting = accumulator.bots_waiting_for_charge

  accumulator.bots_charging = bots_charging + cell.charging_robot_count
  accumulator.bots_waiting_for_charge = bots_waiting + cell.to_charge_robot_count

  -- Check the bots stationed at this roboport
  if cell.owner and cell.owner.valid and player_table.settings.gather_quality_data then
    -- Count roboport quality
    local rp_quality = cell.owner.quality.name
    accumulate_quality(accumulator.roboport_qualities, rp_quality, 1)

    -- Count quality of charging bots
    for _, bot in pairs(cell.charging_robots) do
      if bot.valid and bot.quality then
        local quality = bot.quality.name or "normal"
        accumulate_quality(accumulator.charging_bot_qualities, quality, 1)
      end
    end

    -- Count quality of bots waiting to charge
    for _, bot in pairs(cell.to_charge_robots) do
      if bot.valid and bot.quality then
        local quality = bot.quality.name or "normal"
        accumulate_quality(accumulator.waiting_bot_qualities, quality, 1)
      end
    end

    -- Count quality of bots inside roboports (i.e. idle ones)
    local bot_qualities = accumulator.idle_bot_qualities
    local rp = cell.owner
    if rp then
      inventory = rp.get_inventory(defines.inventory.roboport_robot)
      if not inventory.is_empty() then
        stacks = inventory.get_contents()
        for _, stack in pairs(stacks) do
          if stack.name == "logistic-robot" then
            local quality = stack.quality or "normal"
            accumulate_quality(bot_qualities, quality, stack.count)
          end
        end
      end
    end
  end
end

local function network_chunks_done(accumulator, player_table)
  local bot_items = storage.bot_items
  bot_items["charging-robot"] = accumulator.bots_charging
  bot_items["waiting-for-charge-robot"] = accumulator.bots_waiting_for_charge

  storage.idle_bot_qualities = accumulator.idle_bot_qualities or {}
  storage.roboport_qualities = accumulator.roboport_qualities or {}
  storage.charging_bot_qualities = accumulator.charging_bot_qualities or {}
  storage.waiting_bot_qualities = accumulator.waiting_bot_qualities or {}
end

local activity_chunker = require("scripts.chunker").new(network_initialise, process_one_cell, network_chunks_done)

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
