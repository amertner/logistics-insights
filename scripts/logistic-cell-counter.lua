-- Iterates over all logistic cells in a network, gathering stats
local logistic_cell_counter = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local utils = require("scripts.utils")
local chunker = require("scripts.chunker")
local scheduler = require("scripts.scheduler")

---@class CellAccumulator
---@field bots_charging number Count of bots currently charging
---@field bots_waiting_for_charge number Count of bots waiting to charge
---@field idle_bot_qualities QualityTable Quality counts of idle bots in roboports
---@field roboport_qualities QualityTable Quality counts of roboports
---@field charging_bot_qualities QualityTable Quality counts of charging bots
---@field waiting_bot_qualities QualityTable Quality counts of bots waiting to charge
---@field total_cells number Total number of cells processed

--- Initialize the cell network accumulator
--- @param accumulator CellAccumulator The accumulator to initialize
local function initialise_cell_network_list(accumulator)
  accumulator.bots_charging = 0
  accumulator.bots_waiting_for_charge = 0
  accumulator.idle_bot_qualities = {} -- Gather quality of idle bots
  accumulator.roboport_qualities = {} -- Gather quality of roboports
  accumulator.charging_bot_qualities = {} -- Gather quality of charging bots
  accumulator.waiting_bot_qualities = {} -- Gather quality of bots waiting to charge
  accumulator.total_cells = 0 -- Total number of cells
end

--- Process one logistic cell to gather statistics
--- @param cell LuaLogisticCell The logistic cell to process
--- @param accumulator CellAccumulator The accumulator for gathering statistics
--- @param gather GatherOptions Whether to gather quality data
--- @param networkdata LINetworkData The network data associated with this cell
--- @return number Return number of "processing units" consumed, default is 1
local function process_one_cell(cell, accumulator, gather, networkdata)
  local consumed = 0
  local bots_charging = accumulator.bots_charging
  local bots_waiting = accumulator.bots_waiting_for_charge

  accumulator.bots_charging = bots_charging + cell.charging_robot_count
  accumulator.bots_waiting_for_charge = bots_waiting + cell.to_charge_robot_count
  accumulator.total_cells = accumulator.total_cells + 1

  -- Check the bots stationed at this roboport
  if cell.owner and cell.owner.valid and gather.quality then
    consumed = 1
    -- Count roboport quality
    local rp_quality = (cell.owner.quality and cell.owner.quality.name) or "normal"
    utils.accumulate_quality(accumulator.roboport_qualities, rp_quality, 1)

    -- Count quality of charging bots (fast path: numeric loop + cached locals)
    do
      local list = cell.charging_robots
      if list then
        local cq = accumulator.charging_bot_qualities
        local accq = utils.accumulate_quality
        local count = #list
        consumed = consumed + count/50 -- Count 1 processing unit per 50 bots
        for i = 1, count do
          local bot = list[i]
          if bot and bot.valid and bot.quality then
            local q = bot.quality.name
            accq(cq, q, 1)
          end
        end
      end
    end

    -- Count quality of bots waiting to charge (fast path: numeric loop + cached locals)
    do
      local list = cell.to_charge_robots
      if list then
        local wq = accumulator.waiting_bot_qualities
        local accq = utils.accumulate_quality
        local count = #list
        consumed = consumed + count/50 -- Count 1 processing unit per 50 bots
        for i = 1, count do
          local bot = list[i]
          if bot and bot.valid and bot.quality then
            local q = bot.quality.name
            accq(wq, q, 1)
          end
        end
      end
    end

    -- Count quality of bots inside roboports (i.e. idle ones)
    local bot_qualities = accumulator.idle_bot_qualities
    local rp = cell.owner
    if rp then
      local inventory = rp.get_inventory(defines.inventory.roboport_robot)
      if inventory and not inventory.is_empty() then
        local count = #inventory
        consumed = consumed + count/30 -- Count 1 processing unit per 50 stacks
        for i = 1, count do
          local stack = inventory[i]
          if stack and stack.valid_for_read and stack.name == "logistic-robot" then
            local quality = (stack.quality and stack.quality.name) or "normal"
            utils.accumulate_quality(bot_qualities, quality, stack.count)
          end
        end
      end
    end
  end
  return math.floor(consumed)
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
    networkdata.total_cells = accumulator.total_cells or 0
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
    local networkdata = network_data.create_networkdata(network)
    if not networkdata then
      return
    end

    networkdata.cell_chunker:reset(networkdata, initialise_cell_network_list, all_chunks_done)
    network_data.init_logistic_cell_counter_storage(player_table.network)
    networkdata.suggestions:clear_suggestions()
  end
end

--- PROCESSING A PLAYER NETWORK, AKA FOREGROUND

---@param networkdata LINetworkData
---@param network LuaLogisticNetwork
function logistic_cell_counter.init_foreground_processing(networkdata, network)
  local gather_activity = false
  -- If at least one players in the network has not disabled activity, gather it
  for idx, _ in pairs(networkdata.players_set) do
    local player_table = player_data.get_player_table(idx)
    if player_table then
      gather_activity = true
    end
  end
  -- Store basic network stats
  networkdata.bot_items["logistic-robot-total"] = network.all_logistic_robots
  networkdata.bot_items["logistic-robot-available"] = network.available_logistic_robots

  if gather_activity then
    networkdata.cell_chunker:initialise_chunking(networkdata, network.cells, nil, {}, initialise_cell_network_list)
  end
end

--- BACKGROUND NETWORK PROCESSING

-- Initialise background processing of a network
---@param networkdata LINetworkData
---@param network LuaLogisticNetwork
function logistic_cell_counter.init_background_processing(networkdata, network)
  -- Initialise the chunker for background processing
  local gather_options = {}
  if global_data.gather_quality_data() then
    gather_options.quality = true
  end

  -- Store basic network stats
  networkdata.bot_items["logistic-robot-total"] = network.all_logistic_robots
  networkdata.bot_items["logistic-robot-available"] = network.available_logistic_robots

  logistic_cell_counter.restart_counting(networkdata)
  networkdata.cell_chunker:initialise_chunking(networkdata, network.cells, nil, gather_options, initialise_cell_network_list)
end

--- NETWORK PROCESSING IN CHUNKS

---@param networkdata LINetworkData|nil
---@return boolean True if the network is fully processed, false if there is more data to process
function logistic_cell_counter.is_scanning_done(networkdata)
  if not networkdata or not networkdata.cell_chunker then
    return true
  end

  return networkdata.cell_chunker:is_done_processing()
end

-- Process a single chunk of background network data
---@param networkdata LINetworkData
function logistic_cell_counter.process_next_chunk(networkdata)
  -- Process the background network data
  networkdata.cell_chunker:process_chunk(process_one_cell)
  if networkdata.cell_chunker:needs_finalisation() then
    networkdata.cell_chunker:finalise_run(all_chunks_done)
  end
end


return logistic_cell_counter
