--- Coordinator for all secondary analysis tasks (Undersupply and suggestions)

local analysis_coordinator = {}

local network_data = require("network-data")
local player_data = require("player-data")
local capability_manager = require("capability-manager")
local chunker = require("chunker")
local suggestions_calc = require("suggestions-calc")
local undersupply = require("undersupply")


-- Find network to start analysing, if any
---@return LINetworkData|nil The network data to analyse, or nil if none found
function analysis_coordinator.find_network_to_analyse()
  if storage.analysing_networkdata then
    return nil -- Already analysing a network
  end
  -- Only refresh non-player networks that have not been refreshed for at least refresh-interval
  local last_bg_tick = game.tick - settings.global["li-background-refresh-interval"].value * 60
  local last_fg_tick = game.tick - 2*60 -- At least 2 seconds between foreground analyses

  local last_tick
  local list = {}
  if storage.networks then
    for _, networkdata in pairs(storage.networks) do
      if networkdata then
        local has_players = table_size(networkdata.players_set) > 0
        if has_players then
          last_tick = last_fg_tick
        else
          last_tick = last_bg_tick
        end
        -- Check if the network still exists - might have been removed!
        local nw = network_data.get_LuaNetwork(networkdata)
        if not nw or not nw.valid then
          -- The network no longer exists, so remove it from storage
          network_data.remove_network(networkdata.id)
        elseif networkdata.last_analysed_tick < last_tick then
          -- It's a network with players, or it's not been updated for a long time
          if has_players or not networkdata.bg_paused then
            -- If it has players or it's not paused for bg scan, add it to the candidate list
            list[#list+1] = networkdata
          end
        end
      end
    end
  else
    return nil -- No networks available
  end

  if #list == 0 then
    return nil -- No networks need a background scan
  end
  -- Sort by last active tick, so the oldest networks are scanned first
  table.sort(list, function(a,b) return (a.last_analysed_tick or 0) < (b.last_analysed_tick or 0) end)

  if #list > 0 then
    -- Return the first network in the sorted list
    return list[1]
  else
    return nil -- No networks need analysis
  end
end

-- Check if we are currently analysing this player's network
function analysis_coordinator.is_analysing_player_network(player_table)
  if not storage.analysing_networkdata or not player_table or not player_table.network then
    return false
  end

  return storage.analysing_networkdata.id == player_table.network.network_id
end

-- Start analysis of a network
function analysis_coordinator.start_analysis(networkdata)
  local network = network_data.get_LuaNetwork(networkdata)
  if network then
    storage.analysing_network = network
    storage.analysing_networkdata = networkdata
    storage.analysis_start_tick = game.tick
    storage.analysis_state = {
      free_suggestions_done = false,
      undersupply_analysis_done = false,
      undersupply_chunker = nil,
      storage_analysis_done = false,
      storage_chunker = nil,
    }
  end
end

-- Stop ongoing analysis
function analysis_coordinator.stop_analysis()
  if storage.analysis_state and storage.analysing_networkdata then
    storage.analysing_networkdata.last_analysed_tick = game.tick
  end
  storage.analysing_networkdata = nil
  storage.analysing_network = nil
  storage.analysis_start_tick = nil
  storage.analysis_state = nil
end

-- Run a step of the analysing the current network
function analysis_coordinator.run_analysis_step()
  if not storage.analysing_networkdata then
    return
  end

  local state = storage.analysis_state
  if state.free_suggestions_done == false then
    state.free_suggestions_done = analysis_coordinator.run_free_suggestions_step()
  elseif state.undersupply_analysis_done == false then
    state.undersupply_analysis_done = analysis_coordinator.run_undersupply_step()
  elseif state.storage_analysis_done == false then
    state.storage_analysis_done = analysis_coordinator.run_storage_analysis_step()
  else
    -- All steps are done
    analysis_coordinator.stop_analysis()
  end
end

-- Run all of the suggestions that run in O(1) time
function analysis_coordinator.run_free_suggestions_step()
  local nwd = storage.analysing_networkdata
  if nwd then
    local waiting_to_charge_count = (nwd.bot_items and nwd.bot_items["waiting-for-charge-robot"]) or 0
    suggestions_calc.analyse_waiting_to_charge(nwd.suggestions, waiting_to_charge_count)

    suggestions_calc.analyse_too_many_bots(nwd.suggestions, nwd.network)
  end
  return true
end

function analysis_coordinator.run_storage_analysis_step()
  local networkdata = storage.analysing_networkdata
  local network = storage.analysing_network
  if not networkdata or not network then
    return true -- Nothing to do, so done
  end
  if not storage.analysis_state.storage_chunker then
    -- If this is a foreground network, and all players watching it have paused undersupply, skip
    if player_data.is_foreground_network_paused_for_capability(networkdata, "suggestions", "show_suggestions") then
      return true -- Skip undersupply analysis
    end
    storage.analysis_state.storage_chunker = chunker.new()
  end
  local the_chunker = storage.analysis_state.storage_chunker
  if the_chunker == nil then
    return true -- Could not create chunker, so abort
  end

  if the_chunker:needs_data() then
    the_chunker:initialise_chunking(networkdata, network.storages, nil, {}, suggestions_calc.initialise_storage_analysis)
    return false -- Not done yet
  end

  if the_chunker:needs_processing() then
    the_chunker:process_chunk(suggestions_calc.process_storage_for_analysis)
    return false -- Not done yet
  end

  if the_chunker:needs_finalisation() then
    the_chunker:finalise_run(suggestions_calc.all_storage_chunks_done)

    networkdata.suggestions:update_tick()
  end

  if the_chunker:is_done_processing() then
    storage.analysis_state.storage_chunker = nil
    return true
  end
  return false
end

function analysis_coordinator.run_undersupply_step()
  local networkdata = storage.analysing_networkdata
  local network = storage.analysing_network
  if not networkdata or not network then
    return true -- Nothing to do, so done
  end
  if not storage.analysis_state.undersupply_chunker then
    -- If this is a foreground network, and all players watching it have paused undersupply, skip
    if player_data.is_foreground_network_paused_for_capability(networkdata, "undersupply", "show_undersupply") then
      return true -- Skip undersupply analysis
    end
    storage.analysis_state.undersupply_chunker = chunker.new()
  end
  local the_chunker = storage.analysis_state.undersupply_chunker
  if the_chunker == nil then
    return true -- Could not create chunker, so abort
  end

  if the_chunker:needs_data() then
    the_chunker:initialise_chunking(networkdata, network.requesters, networkdata.bot_deliveries, {}, undersupply.initialise_undersupply)
    return false -- Not done yet
  end

  if the_chunker:needs_processing() then
    the_chunker:process_chunk(undersupply.process_one_requester)
    return false -- Not done yet
  end

  if the_chunker:needs_finalisation() then
    the_chunker:finalise_run(undersupply.all_chunks_done)

    networkdata.suggestions:set_cached_list("undersupply", the_chunker:get_partial_data().net_demand)
    networkdata.suggestions:update_tick()
  end

  if the_chunker:is_done_processing() then
    storage.analysis_state.undersupply_chunker = nil
    return true
  end
  return false
end

return analysis_coordinator
