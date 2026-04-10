--- Coordinator for all secondary analysis tasks (Undersupply and suggestions)

local analysis_coordinator = {}

local network_data = require("scripts.network-data")
local player_data = require("scripts.player-data")
local global_data = require("scripts.global-data")
local chunker = require("scripts.chunker")
local suggestions_calc = require("scripts.suggestions-calc")
local undersupply = require("scripts.undersupply")
local debugger = require("scripts.debugger")
local bench_profiler = require("scripts.bench-profiler")


-- Find network to start analysing, if any
---@return LINetworkData|nil The network data to analyse, or nil if none found
function analysis_coordinator.find_network_to_analyse()
  if storage.analysing_networkdata then
    return nil -- Already analysing a network
  end
  -- Only refresh non-player networks that have not been refreshed for at least refresh-interval
  local last_bg_tick
  if global_data.background_scans_disabled() then
    last_bg_tick = 0 -- Don't analyse any background networks
  else
    last_bg_tick = game.tick - global_data.background_refresh_interval_ticks()
  end
  local last_fg_tick = game.tick - 2*60 -- At least 2 seconds between foreground analyses

  if not storage.networks then
    return nil -- No networks available
  end

  -- Single-pass selection: foreground networks (with active players) always
  -- take priority over background networks; within the same tier, oldest wins.
  local best_candidate = nil
  local best_last_analysed = nil
  local best_is_foreground = false

  for _, networkdata in pairs(storage.networks) do
    if networkdata then
      local has_players = next(networkdata.players_set) ~= nil
      local is_foreground = has_players and player_data.players_show_main_window(networkdata.players_set)
      local threshold_tick = has_players and last_fg_tick or last_bg_tick

      local last_analysed = networkdata.last_analysed_tick or 0
      if last_analysed < threshold_tick then
        if is_foreground or global_data.background_scans_enabled() then
          -- Foreground always beats background; within same tier, oldest wins
          if not best_candidate
              or (is_foreground and not best_is_foreground)
              or (is_foreground == best_is_foreground and last_analysed < best_last_analysed) then
            best_candidate = networkdata
            best_last_analysed = last_analysed
            best_is_foreground = is_foreground
          end
        end
      end
    end
  end

  return network_data.validate_or_remove(best_candidate)
end

-- Check if we are currently analysing this player's network
function analysis_coordinator.is_analysing_player_network(player_table)
  if not storage.analysing_networkdata or not player_table or not player_table.network or not player_table.network.valid then
    return false
  end

  return storage.analysing_networkdata.id == player_table.network.network_id
end

-- Start analysis of a network
function analysis_coordinator.start_analysis(networkdata)
  local network = network_data.get_LuaNetwork(networkdata)
  if network then
    debugger.info("[analysis-coordinator] Starting analysis for network " .. tostring(networkdata.id))
    -- Cache provider count while we have the network reference
    networkdata.provider_count = #network.providers
    storage.analysing_network = network
    storage.analysing_networkdata = networkdata
    storage.analysis_start_tick = game.tick
    storage.analysis_state = {
      free_suggestions_done = false,
      -- If undersupply calculation is disabled, mark it as done immediately
      undersupply_analysis_done = not global_data.calculate_undersupply(),
      undersupply_chunker = nil,
      storage_analysis_done = false,
      storage_chunker = nil,
    }
  end
end

-- Stop ongoing analysis
function analysis_coordinator.stop_analysis()
  if storage.analysis_state and storage.analysing_networkdata and storage.analysing_network and storage.analysing_network.valid then
    storage.analysing_networkdata.last_analysed_tick = game.tick
  end
  storage.analysing_networkdata = nil
  storage.analysing_network = nil
  storage.analysis_start_tick = nil
  storage.analysis_state = nil
end

-- Run a step of the analysing the current network
function analysis_coordinator.run_analysis_step()
  if not storage.analysing_networkdata or not storage.analysing_network or not storage.analysing_network.valid then
    if storage.analysing_networkdata then
      debugger.info("[analysis-coordinator] Stopping for nil or invalid network " .. tostring(storage.analysing_networkdata.id))
    end
    analysis_coordinator.stop_analysis()
    return
  end
  debugger.info("[analysis-coordinator] Running analysis step for network " .. tostring(storage.analysing_networkdata.id))

  local state = storage.analysis_state
  if state.free_suggestions_done == false then
    state.free_suggestions_done = bench_profiler.measure("analysis:free-suggestions", analysis_coordinator.run_free_suggestions_step)
  elseif state.storage_analysis_done == false then
    state.storage_analysis_done = bench_profiler.measure("analysis:storage", analysis_coordinator.run_storage_analysis_step)
  elseif state.undersupply_analysis_done == false then
    state.undersupply_analysis_done = bench_profiler.measure("analysis:undersupply", analysis_coordinator.run_undersupply_step)
  else
    -- All steps are done
    debugger.info("[analysis-coordinator] Complete for network " .. tostring(storage.analysing_networkdata.id))
    analysis_coordinator.stop_analysis()
  end
end

-- Run all of the suggestions that run in O(1) time
function analysis_coordinator.run_free_suggestions_step()
  local nwd = storage.analysing_networkdata
  if nwd then
    local waiting_to_charge_count = (nwd.bot_items and nwd.bot_items["waiting-for-charge-robot"]) or 0
    suggestions_calc.analyse_waiting_to_charge(nwd.suggestions, waiting_to_charge_count)

    suggestions_calc.analyse_too_many_bots(nwd.suggestions, storage.analysing_network)
    suggestions_calc.analyse_too_few_bots(nwd.suggestions, storage.analysing_network)

    suggestions_calc.analyse_unpowered_roboports(nwd.suggestions, nwd.unpowered_roboport_list)
  end
  return true
end

function analysis_coordinator.run_storage_analysis_step()
  local networkdata = storage.analysing_networkdata
  local network = storage.analysing_network
  if not networkdata or not network or not network.valid then
    return true -- Nothing to do, so done
  end
  if not storage.analysis_state.storage_chunker or not storage.analysis_state.storage_chunker.state then
    storage.analysis_state.storage_chunker = chunker.new()
  end
  local the_chunker = storage.analysis_state.storage_chunker

  if the_chunker:needs_data() then
    local net = network
    the_chunker:initialise_chunking(networkdata.id,
      function() return net.valid and net.storages or {} end,
      { ignored_storages_for_mismatch = networkdata.ignored_storages_for_mismatch,
        ignore_higher_quality_mismatches=networkdata.ignore_higher_quality_mismatches,
        ignore_low_storage_when_no_storage=networkdata.ignore_low_storage_when_no_storage },
      {}, suggestions_calc.initialise_storage_analysis, global_data.analysis_chunk_divisor(), "storage")
    return false -- Not done yet
  end

  if the_chunker:needs_processing() then
    the_chunker:process_chunk(suggestions_calc.process_storage_for_analysis)
    return false -- Not done yet
  end

  if the_chunker:needs_finalisation() then
    networkdata.storage_count = the_chunker.processing_count
    the_chunker:finalise_run(suggestions_calc.all_storage_chunks_done)
    networkdata.suggestions:update_tick()
  end

  if the_chunker:is_done_processing() then
    return true
  end
  return false
end

function analysis_coordinator.run_undersupply_step()
  local networkdata = storage.analysing_networkdata
  local network = storage.analysing_network
  if not networkdata or not network or not network.valid then
    return true -- Nothing to do, so done
  end
  if not storage.analysis_state.undersupply_chunker or not storage.analysis_state.undersupply_chunker.state then
    storage.analysis_state.undersupply_chunker = chunker.new()
  end
  local the_chunker = storage.analysis_state.undersupply_chunker

  if the_chunker:needs_data() then
    -- Drop stale cache entries when size exceeds 2x live count (rare).
    local cache = networkdata.requester_cache
    local live_count = networkdata.requester_count or 0
    if table_size(cache) > 2 * (live_count + 16) then
      for unit_number, entry in pairs(cache) do
        if game.tick - entry.refresh_tick > 60 * 60 * 5 then
          cache[unit_number] = nil
        end
      end
    end

    -- Bump the per-network rolling-sweep counter once per undersupply pass.
    -- Per-network (not global) so that re-analysing the same network back-to-back
    -- still rotates through different slices, preserving the N-sweep coverage
    -- guarantee. Lazy-init for save/load migration safety on older networks.
    local sweep = (networkdata.undersupply_sweep_counter or 0) + 1
    networkdata.undersupply_sweep_counter = sweep
    local rolling_divisor = global_data.undersupply_rolling_divisor()

    local context = {deliveries = networkdata.bot_deliveries,
      ignored_items = networkdata.ignored_items_for_undersupply,
      ignore_buffer_chests_for_undersupply = networkdata.ignore_buffer_chests_for_undersupply,
      requester_cache = cache,
      rolling_divisor = rolling_divisor,
      slice_id = sweep % rolling_divisor}
    context.ignore_player_demands = global_data.ignore_player_demands_in_undersupply()

    local net = network
    the_chunker:initialise_chunking(networkdata.id,
      function() return net.valid and net.requesters or {} end,
      context, {}, undersupply.initialise_undersupply, global_data.analysis_chunk_divisor(), "undersupply")
    return false -- Not done yet
  end

  if the_chunker:needs_processing() then
    the_chunker:process_chunk(undersupply.process_one_requester)
    return false -- Not done yet
  end

  if the_chunker:needs_finalisation() then
    networkdata.requester_count = the_chunker.processing_count
    the_chunker:finalise_run(undersupply.all_chunks_done)
    networkdata.suggestions:set_cached_list("undersupply", the_chunker:get_partial_data().net_demand)
    networkdata.suggestions:update_tick()
  end

  if the_chunker:is_done_processing() then
    return true
  end
  return false
end

return analysis_coordinator
