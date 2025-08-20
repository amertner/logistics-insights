-- Iterates over all logistic cells in a network, gathering stats
local logistic_cell_counter = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local utils = require("scripts.utils")
local chunker = require("scripts.chunker")

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
--- @param gather GatherOptions Whether to gather quality data
--- @param networkdata LINetworkData The network data associated with this cell
local function process_one_cell(cell, accumulator, gather, networkdata)
  local bots_charging = accumulator.bots_charging
  local bots_waiting = accumulator.bots_waiting_for_charge

  accumulator.bots_charging = bots_charging + cell.charging_robot_count
  accumulator.bots_waiting_for_charge = bots_waiting + cell.to_charge_robot_count

  -- Check the bots stationed at this roboport
  if cell.owner and cell.owner.valid and gather.quality then
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
      local inventory = rp.get_inventory(defines.inventory.roboport_robot)
      if inventory and not inventory.is_empty() then
        local stacks = inventory.get_contents()
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
--- @param gather GatherOptions for what to gather
--- @param networkdata LINetworkData The network data to update with results
local function all_chunks_done(accumulator, gather, networkdata)
  if networkdata then
    local bot_items = networkdata.bot_items
    bot_items["charging-robot"] = accumulator.bots_charging
    bot_items["waiting-for-charge-robot"] = accumulator.bots_waiting_for_charge

    networkdata.idle_bot_qualities = accumulator.idle_bot_qualities or {}
    networkdata.roboport_qualities = accumulator.roboport_qualities or {}
    networkdata.charging_bot_qualities = accumulator.charging_bot_qualities or {}
    networkdata.waiting_bot_qualities = accumulator.waiting_bot_qualities or {}
  end
end

--- Process data gathered so far and start over
--- @param networkdata LINetworkData|nil The network data to reset
function logistic_cell_counter.restart_counting(networkdata)
  if networkdata then
    networkdata.cell_chunker:reset(networkdata, initialise_cell_network_list, all_chunks_done)
  end
end

--- Reset logistic cell data when network changes
--- @param player? LuaPlayer The player whose network changed
--- @param player_table? PlayerData The player's data table
function logistic_cell_counter.network_changed(player, player_table)
  if player_table then
    local network = player_table.network
    if not network or not network.valid then
      return
    end
    local networkdata = network_data.get_networkdata(network)
    if not networkdata then
      return
    end

    networkdata.cell_chunker:reset(networkdata, initialise_cell_network_list, all_chunks_done)
    network_data.init_logistic_cell_counter_storage(player_table.network)
    networkdata.suggestions:clear_suggestions()
  end
end

--- Gather activity data from all cells in this player's network
--- @param player? LuaPlayer The player to gather data for
--- @param player_table? PlayerData The player's data table containing network and settings
--- @return Progress A table with current and total progress values
function logistic_cell_counter.gather_data_for_player_network(player, player_table)
  -- First update and validate network
  local progress = { current = 0, total = 0 } -- Use local variable to avoid global access
  if not player_table then
    return progress -- Ignore if no player_table is provided
  end
  if not player_table.settings.show_activity then
    return progress -- Activity gathering is disabled in settings
  end

  local network = player_table.network
  if not network or not network.valid then
    return progress
  end
  local networkdata = network_data.get_networkdata(network)
  if not networkdata then
    return progress -- No valid network data available
  end

  -- Store basic network stats
  networkdata.bot_items["logistic-robot-total"] = network.all_logistic_robots
  networkdata.bot_items["logistic-robot-available"] = network.available_logistic_robots

  local cell_chunker = networkdata.cell_chunker
  -- Process cell data
  if cell_chunker:is_done() then
    -- Prior pass was done, so start a new pass
    cell_chunker:initialise_chunking(networkdata, network.cells, nil, {}, initialise_cell_network_list)
  end
  cell_chunker:process_chunk(process_one_cell, all_chunks_done)

  return cell_chunker:get_progress()
end

--- BACKGROUND NETWORK PROCESSING

---@param networkdata LINetworkData|nil
---@return boolean True if the network is fully processed, false if there is more data to process
function logistic_cell_counter.is_background_done(networkdata)
  if not networkdata then
    return true
  end

  local bot_chunker = networkdata.bot_chunker
  if not bot_chunker then
    return true
  end

  return bot_chunker:is_done()
end

-- Initialise background processing of a network
---@param networkdata LINetworkData
---@param network LuaLogisticNetwork
function logistic_cell_counter.init_background_processing(networkdata, network)
  -- Initialise the chunker for background processing
  local gather_options = {}
  if settings.global["li-gather-quality-data-global"].value then
    gather_options.quality = true
  end

  -- Store basic network stats
  networkdata.bot_items["logistic-robot-total"] = network.all_logistic_robots
  networkdata.bot_items["logistic-robot-available"] = network.available_logistic_robots

  logistic_cell_counter.restart_counting(networkdata)
  networkdata.cell_chunker:initialise_chunking(networkdata, network.cells, nil, {}, initialise_cell_network_list)
end

-- Process a single chunk of background network data
---@param networkdata LINetworkData
function logistic_cell_counter.process_background_network(networkdata)
  -- Process the background network data
  networkdata.cell_chunker:process_chunk(process_one_cell, all_chunks_done)
  return true
end


return logistic_cell_counter
