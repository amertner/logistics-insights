--- Coordinator for all primary scanning tasks (Bots and cells), foreground and background

local scan_coordinator = {}

local network_data = require("network-data")
local player_data = require("player-data")
local global_data = require("global-data")
local bot_counter = require("bot-counter")
local logistic_cell_counter = require("logistic-cell-counter")
local main_window = require("scripts.mainwin.main_window")

-- BACKGROUND SCANNING

-- Called often to refresh background networks. Do at most one chunk of work per call.
function scan_coordinator.background_refresh()
  if storage.bg_refreshing_network_id then
    -- We're refreshing a network already
    local networkdata = network_data.get_networkdata_fromid(storage.bg_refreshing_network_id)
    if networkdata then
      if bot_counter.is_scanning_done(networkdata) then        
        -- The bot counter is finished; process the logistic cells
        if logistic_cell_counter.is_scanning_done(networkdata) then
          -- Signal that the background refresh is done
          storage.bg_refreshing_network_id = nil
          network_data.finished_scanning_network(networkdata)
        else
          logistic_cell_counter.process_next_chunk(networkdata)
        end
      else
        bot_counter.process_next_chunk(networkdata)
      end
    else
      -- The network is no longer valid, so stop refreshing it
      storage.bg_refreshing_network_id = nil
    end
  else
    -- No background network is being refreshed; find one to refresh
    local networkdata = network_data.get_next_background_network()
    if networkdata then
      local network = network_data.get_LuaNetwork(networkdata)
      if network then
        storage.bg_refreshing_network_id = networkdata.id
        bot_counter.init_background_processing(networkdata, network)
        logistic_cell_counter.init_background_processing(networkdata, network)
      end
    end
  end
end

-- Update the progress bars for a chunker for all players observing it
---@param networkdata LINetworkData The network data being scanned
---@param chunker Chunker The chunker being processed
---@param update_fn function The function to call to update the progress bar for a player
local function update_progressbars_for_network(networkdata, chunker, update_fn)
  if not networkdata or not chunker or not update_fn then
    return
  end
  for player_index, _ in pairs(networkdata.players_set) do
    local player = game.get_player(player_index)
    local player_table = player_data.get_player_table(player_index)
    if player and player.valid and player_table then
      update_fn(player_table, chunker:get_progress())
    end
  end
end

-- FOREGROUND SCANNING

-- Called often to refresh foreground networks. Do at most one chunk of work per call.
---@param network_id number
function scan_coordinator.foreground_bot_chunk(network_id)
  if network_id then
    local networkdata = network_data.get_networkdata_fromid(network_id)
    if networkdata then
      if not bot_counter.is_scanning_done(networkdata) then
        bot_counter.process_next_chunk(networkdata)
        update_progressbars_for_network(networkdata, networkdata.bot_chunker, main_window.update_bot_progress)
      end
    else
      -- The network is no longer valid, so stop refreshing it
      storage.fg_refreshing_network_id = nil
    end
  end
end

-- Called often to refresh foreground networks. Do at most one chunk of work per call.
---@param network_id number
function scan_coordinator.foreground_cell_chunk(network_id)
  if network_id then
    local networkdata = network_data.get_networkdata_fromid(network_id)
    if networkdata then
      if not logistic_cell_counter.is_scanning_done(networkdata) then
        logistic_cell_counter.process_next_chunk(networkdata)
        update_progressbars_for_network(networkdata, networkdata.cell_chunker, main_window.update_cells_progress)
      end
    else
      -- The network is no longer valid, so stop refreshing it
      storage.fg_refreshing_network_id = nil
    end
  end
end

-- STARTING A NEW FOREGROUND SCAN

-- If we're doing a background refresh, abandon it and start analysing this fg network instead
---@param player_table PlayerData The player's data table
function scan_coordinator.prioritise_scanning_new_player_network(player_table)
  if not player_table or not player_table.network then
    -- Nothing to do if player is not in network
    return
  end
  local network_id = player_table.network.network_id
  if storage.bg_refreshing_network_id then
    -- We're doing a background scan; abandon that and start on the player's network instead
    local networkdata = network_data.get_networkdata(player_table.network)
    if networkdata then
      storage.bg_refreshing_network_id = nil
      storage.fg_refreshing_network_id = networkdata.id
      bot_counter.init_foreground_processing(networkdata, player_table.network)
      logistic_cell_counter.init_foreground_processing(networkdata, player_table.network)
    end
  end
end

function scan_coordinator.initiate_next_player_network_scan()
  -- Check if currently processing network is done
  if storage.fg_refreshing_network_id then
    networkdata = network_data.get_networkdata_fromid(storage.fg_refreshing_network_id)
    if networkdata then
      if networkdata.bot_chunker:is_done_processing() and networkdata.cell_chunker:is_done_processing() then
        -- The previous network is fully processed, so we can move to the next one
        storage.fg_refreshing_network_id = nil
        network_data.finished_scanning_network(networkdata)
      else
        return -- Still processing the current network, so don't switch yet
      end
    end
  end

  -- Check what the next network should be
  if not storage.fg_refreshing_network_id then
    local networkdata = network_data.get_next_player_network()
    if networkdata then
      local network = network_data.get_LuaNetwork(networkdata)
      if network then
        storage.fg_refreshing_network_id = networkdata.id
        bot_counter.init_foreground_processing(networkdata, network)
        logistic_cell_counter.init_foreground_processing(networkdata, network)
      end
    end
  end
end

return scan_coordinator