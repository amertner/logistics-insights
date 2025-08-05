-- Iterates over all logistic cells in a network, gathering stats
local logistic_cell_counter = {}

local player_data = require("scripts.player-data")
local utils = require("scripts.utils")

---@class CellAccumulator
---@field bots_charging number Count of bots currently charging
---@field bots_waiting_for_charge number Count of bots waiting to charge
---@field idle_bot_qualities QualityTable Quality counts of idle bots in roboports
---@field roboport_qualities QualityTable Quality counts of roboports
---@field charging_bot_qualities QualityTable Quality counts of charging bots
---@field waiting_bot_qualities QualityTable Quality counts of bots waiting to charge

--- Initialize the cell network accumulator
--- @param accumulator CellAccumulator The accumulator to initialize
local function initialise_cell_network_list(accumulator)
  accumulator.bots_charging = 0
  accumulator.bots_waiting_for_charge = 0
  accumulator.idle_bot_qualities = {} -- Gather quality of idle bots
  accumulator.roboport_qualities = {} -- Gather quality of roboports
  accumulator.charging_bot_qualities = {} -- Gather quality of charging bots
  accumulator.waiting_bot_qualities = {} -- Gather quality of bots waiting to charge
end

--- Process one logistic cell to gather statistics
--- @param cell LuaLogisticCell The logistic cell to process
--- @param accumulator CellAccumulator The accumulator for gathering statistics
--- @param player_table PlayerData The player's data table containing settings
local function process_one_cell(cell, accumulator, player_table)
  local bots_charging = accumulator.bots_charging
  local bots_waiting = accumulator.bots_waiting_for_charge

  accumulator.bots_charging = bots_charging + cell.charging_robot_count
  accumulator.bots_waiting_for_charge = bots_waiting + cell.to_charge_robot_count

  -- Check the bots stationed at this roboport
  if cell.owner and cell.owner.valid and player_table.settings.gather_quality_data then
    -- Count roboport quality
    local rp_quality = cell.owner.quality.name
    utils.accumulate_quality(accumulator.roboport_qualities, rp_quality, 1)

    -- Count quality of charging bots
    for _, bot in pairs(cell.charging_robots) do
      if bot.valid and bot.quality then
        local quality = bot.quality.name or "normal"
        utils.accumulate_quality(accumulator.charging_bot_qualities, quality, 1)
      end
    end

    -- Count quality of bots waiting to charge
    for _, bot in pairs(cell.to_charge_robots) do
      if bot.valid and bot.quality then
        local quality = bot.quality.name or "normal"
        utils.accumulate_quality(accumulator.waiting_bot_qualities, quality, 1)
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
            utils.accumulate_quality(bot_qualities, quality, stack.count)
          end
        end
      end
    end
  end
end

--- Complete processing of all chunks and store results
--- @param accumulator CellAccumulator The accumulator containing gathered statistics
--- @param player_table PlayerData The player's data table
local function all_chunks_done(accumulator, player_table)
  local bot_items = storage.bot_items
  bot_items["charging-robot"] = accumulator.bots_charging
  bot_items["waiting-for-charge-robot"] = accumulator.bots_waiting_for_charge

  storage.idle_bot_qualities = accumulator.idle_bot_qualities or {}
  storage.roboport_qualities = accumulator.roboport_qualities or {}
  storage.charging_bot_qualities = accumulator.charging_bot_qualities or {}
  storage.waiting_bot_qualities = accumulator.waiting_bot_qualities or {}

  if player_table and player_table.suggestions then
    player_table.suggestions:cells_data_updated(player_table.network)
  end
end

local cell_chunker = require("scripts.chunker").new(initialise_cell_network_list, process_one_cell, all_chunks_done)

--- Process data gathered so far and start over
function logistic_cell_counter.restart_counting()
  cell_chunker:reset()
end

--- Reset logistic cell data when network changes
--- @param player? LuaPlayer The player whose network changed
--- @param player_table? PlayerData The player's data table
function logistic_cell_counter.network_changed(player, player_table)
  cell_chunker:reset()
  player_data.init_logistic_cell_counter_storage()
  if player_table and player_table.suggestions then
    player_table.suggestions:clear_suggestions()
  end
end

--- Gather activity data from all cells in network
--- @param player? LuaPlayer The player to gather data for
--- @param player_table? PlayerData The player's data table containing network and settings
--- @return Progress A table with current and total progress values
function logistic_cell_counter.gather_data(player, player_table)
  -- First update and validate network
  local progress = { current = 0, total = 0 } -- Use local variable to avoid global access
  if not player_table then
    return progress -- Ignore if no player_table is provided
  end
  local network = player_table.network
  local bot_items = storage.bot_items       -- Cache the table lookup
  if not network or not network.valid then
    return progress
  end

  -- Store basic network stats
  bot_items["logistic-robot-total"] = network.all_logistic_robots
  bot_items["logistic-robot-available"] = network.available_logistic_robots

  if player_data.is_history_paused(player_table) then
    return progress
  end

  -- Process cell data
  if cell_chunker:is_done() then
    cell_chunker:initialise_chunking(network.cells, player_table, nil)
    player_data.set_logistic_cell_chunks(player_table, cell_chunker:num_chunks())
  end
  cell_chunker:process_chunk()

  return cell_chunker:get_progress()
end

return logistic_cell_counter
