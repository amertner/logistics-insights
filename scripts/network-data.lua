--- Manage storage of network data analysed by LI
local network_data = {}

local suggestions = require("scripts.suggestions")
local chunker = require("scripts.chunker")
local tick_counter = require("scripts.tick-counter")
local global_data = require("scripts.global-data")
local player_data = require("scripts.player-data")
local debugger = require("scripts.debugger")
local utils = require("scripts.utils")

-- Data stored for each network
---@class LINetworkData
---@field id number -- The unique ID of the network
---@field surface string -- The surface name where the network is located
---@field force_name string -- The force name of the network
---@field players_set table<number, boolean> -- Set of player indexes active in this network (key = player index)
---@field cell_chunker Chunker -- Chunker for processing logistic cells
---@field bot_chunker Chunker -- Chunker for processing logistic bots
---@field history_timer TickCounter -- Tracks time for collecting delivery history
---@ -- Suggestions and undersupply data
---@field suggestions Suggestions -- The list of suggestions associated with this network
---@ -- Per-network settings
---@field ignored_storages_for_mismatch table<number, boolean> -- A list of storage IDs to ignore for mismatched storage suggestion
---@field ignore_higher_quality_mismatches boolean -- Whether to ignore higher quality mismatches
---@field ignored_items_for_undersupply table<string, boolean> -- A list of "item name:quality" to ignore for undersupply suggestion
---@ -- Data capture fields
---@field last_scanned_tick number -- The last tick this network's cell and bot data was updated
---@field last_analysed_tick number -- The last tick this network's suggestios and undersupply were analysed
---@field last_accessed_tick number -- The last tick this network's data was accessed
---@field last_pass_bots_seen table<number, number> -- A list of bots seen in the last full pass
---@ -- Fields populated by analysing cells
---@field idle_bot_qualities QualityTable Quality of idle bots in roboports
---@field charging_bot_qualities QualityTable Quality of bots currently charging
---@field waiting_bot_qualities QualityTable Quality of bots waiting to charge
---@field roboport_qualities QualityTable Quality of roboports
---@field total_cells number Total number of cells in the network
---@ -- Fields populated by bot_counter
---@field bot_deliveries table<string, DeliveryItem> A list of items being delivered right now
---@field bot_items table<string, number> Real time data about bots: Very cheap to keep track of
---@field bot_active_deliveries table<number, BotDeliveringInFlight> A list of bots currently delivering items
---@field delivery_history table<string, DeliveredItems> A list of past delivered items
---@field picking_bot_qualities QualityTable Quality of bots currently picking items
---@field delivering_bot_qualities QualityTable Quality of bots currently delivering items
---@field other_bot_qualities QualityTable Quality of bots doing anything else 
---@field total_bot_qualities QualityTable Quality of all bots counted

-- Record used to show items being delivered right now
---@class DeliveryItem
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many are being delivered

-- Record used to show historically delivered items
---@class DeliveredItems
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many of this item have been delivered
---@field ticks number -- Total ticks for all deliveries of this item
---@field avg number -- Average ticks per delivery, equal to ticks/count

-- Record used to record items being delivered, before they are added to history
---@class BotDeliveringInFlight
---@field item_name string -- The name of the item being delivered
---@field quality_name? string -- The quality of the item, if applicable
---@field localised_name? LocalisedString -- The localised name of the item
---@field localised_quality_name? LocalisedString -- The localised name of the quality
---@field count number -- How many of this item it is delivering
---@field targetpos MapPosition -- The target position for the delivery
---@field first_seen number -- The first tick this bot was seen delivering it
---@field last_seen number -- The last tick this bot was seen delivering it

-- Record used to store list of undersupplied items
---@class UndersupplyItem
---@field shortage number -- How many of this item is undersupplied
---@field type string -- The type of the item, e.g. "item", "fluid", "entity"
---@field item_name string -- The name of the item
---@field quality_name string -- The quality of the item, if applicable
---@field request number -- The requested amount of this item
---@field supply number -- The available supply of this item
---@field under_way number -- The amount of this item already in transit

function network_data.init()
  ---@type table<uint, LINetworkData>
    storage.networks = {}
end

---@param network LuaLogisticNetwork|nil The network to get data for
function network_data.get_networkdata(network)
  if not network or not network.valid or not network.network_id or not storage.networks then
    return nil -- No network ID or storage available
  end
  local networkdata = storage.networks[network.network_id]
  if not networkdata then
    return nil -- No data for this network
  else
    -- Update last-accessed
    networkdata.last_accessed_tick = game.tick
    return networkdata
  end
end

---@param network_id number|nil The network to get data for
---@return LINetworkData|nil
function network_data.get_networkdata_fromid(network_id)
  if not network_id or not storage.networks then
    return nil -- No network ID or storage available
  end
  local networkdata = storage.networks[network_id]
  if not networkdata then
    return nil -- No data for this network
  else
    -- Update last-accessed
    networkdata.last_accessed_tick = game.tick
    return networkdata
  end
end

---@param network LuaLogisticNetwork|nil The network to create storage for
---@return LINetworkData|nil The created or existing network data
function network_data.create_networkdata(network)
  if not network then
    return nil -- No network supplied
  end
  if not storage.networks then
    storage.networks = {} -- Inialise
  end

  -- Create a new network data entry if it doesn't exist
  if not storage.networks[network.network_id] then
    local game_tick = game.tick
    storage.networks[network.network_id] = {
      id = network.network_id,
      surface = network.cells[1].owner.surface.name or "",
      force_name = network.force.name or "",
      players_set = {},
      cell_chunker = chunker.new(),
      bot_chunker = chunker.new(),
      last_accessed_tick = game_tick,
      last_scanned_tick = game_tick,
      last_analysed_tick = game_tick,
      history_timer = tick_counter.new(),
      suggestions = suggestions.new(),
      ignored_storages_for_mismatch = {},
      ignore_higher_quality_mismatches = false,
      ignored_items_for_undersupply = {},
      last_pass_bots_seen = {},
      idle_bot_qualities = {},
      charging_bot_qualities = {},
      waiting_bot_qualities = {},
      roboport_qualities = {},
      bot_deliveries = {},
      bot_items = {},
      bot_active_deliveries = {},
      delivery_history = {},
      picking_bot_qualities = {},
      delivering_bot_qualities = {},
      other_bot_qualities = {},
      total_bot_qualities = {},
      total_cells = 0
    }
  end
  return storage.networks[network.network_id]
end

-- Initialize all of the storage elements managed by logistic_cell_counter
---@param network LuaLogisticNetwork|nil The network to initialise
---@return nil
function network_data.init_logistic_cell_counter_storage(network)
  local nw = network_data.get_networkdata(network)
  if not nw then
    network_data.create_networkdata(network)
  else
    nw.idle_bot_qualities = {}
    nw.charging_bot_qualities = {}
    nw.waiting_bot_qualities = {}
    nw.roboport_qualities = {}
  end
end

-- Initialize all of the storage elements managed by bot_counter only
---@param network LuaLogisticNetwork|nil The network to initialise
---@return nil
function network_data.init_bot_counter_storage(network)
  local nw = network_data.get_networkdata(network)
  if not nw then
    network_data.create_networkdata(network)
  else
    nw.bot_deliveries = {}
    nw.last_pass_bots_seen = {}
    nw.bot_items = {}
    nw.bot_active_deliveries = {} -- A list of bots currently delivering items
    nw.delivery_history = {} -- A list of past delivered items
    nw.picking_bot_qualities = {} -- Quality of bots currently picking items
    nw.delivering_bot_qualities = {} -- Quality of bots currently delivering items
    nw.other_bot_qualities = {} -- Quality of bots doing anything else
    nw.total_bot_qualities = {} -- Quality of all bots counted
  end
end

--- Clear delivery history for a network, in response to user clicking the "Clear" button
--- @param network LuaLogisticNetwork The network to clear delivery history for
function network_data.clear_delivery_history(network)
  local nwd = network_data.get_networkdata(network)
  if nwd then
    nwd.delivery_history = {} -- Clear the delivery history
    nwd.history_timer:reset() -- Reset the history timer
  end
end

--- Clear delivery history for a network, in response to user clicking the "Clear" button
--- @param networkdata LINetworkData The network to clear delivery history for
function network_data.clear_history_from_nwd(networkdata)
  if networkdata then
    networkdata.delivery_history = {} -- Clear the delivery history
  end
end

--- Clear all bot deliveries for a network, to avoid filling up memory
--- @param max_age_ticks number If a network hasn't been accessed for this many ticks, its data will be cleared
function network_data.clear_old_network_data(max_age_ticks)
  -- Clear old network data that is no longer needed
  local tick_limit = game.tick - max_age_ticks
  for network_id, networkdata in pairs(storage.networks) do
    if networkdata.last_accessed_tick < tick_limit then
      -- Remove the network data if it hasn't been accessed for a long time
      storage.networks[network_id] = nil
    end
  end
end


---@param player LuaPlayer|nil
---@param player_table PlayerData|nil
---@return boolean True if the network has changed, false otherwise
function network_data.check_network_changed(player, player_table)
  if not player or not player.valid then
    return false
  end

  if player_table and player_table.fixed_network then
    -- Check that the fixed network is still valid
    if player_table.network and player_table.network.valid then
      return false
    else
      -- The fixed network is no longer valid, so make sure to clear it
      local nwd = network_data.get_networkdata(player_table.network)
      network_data.remove_player_index_from_networkdata(nwd, player_table)
      player_table.network = nil
      player_table.fixed_network = false
    end
  end

  -- Get or update the network, return true if the network is changed
  if player_table then
    local network = player.force.find_logistic_network_by_position(player.position, player.surface)
    local player_table_network = player_table.network
    -- Get the network IDs, making sure the network references are still valid
    local new_network_id = network and network.valid and network.network_id or 0
    local old_network_id = player_table_network and player_table_network.valid and player_table_network.network_id or 0

    if new_network_id == old_network_id then
      -- Update no_network reason (still evaluate if network exists)
      return false
    else
      network_data.player_changed_networks(player_table, old_network_id, network)
      return true
    end
  else
    return false
  end
end

--- Call this to update the list of players active in a network
---@param player_table PlayerData The player's data table
---@param old_network_id uint|nil The old network ID, if any
---@param new_network LuaLogisticNetwork|nil The new network, if any
function network_data.player_changed_networks(player_table, old_network_id, new_network)
  if not player_table then
    return
  end
  local old_nwd = network_data.get_networkdata_fromid(old_network_id)
  if old_nwd and old_network_id then
    network_data.remove_player_index_from_networkdata(old_nwd, player_table)
    local count = network_data.players_in_network(old_nwd)

    if count == 0 then
      -- No more players observing this network, so clear its history and stop gathering history data
      network_data.clear_history_from_nwd(old_nwd)

      -- As the old network has no players left, potentially remove it
      if global_data.purge_nonplayer_networks() then
        storage.networks[old_network_id] = nil
      end
    end
  end
  local new_nwd = network_data.get_networkdata(new_network)
  if not new_nwd and new_network and new_network.valid then
    new_nwd = network_data.create_networkdata(new_network)
  end
  if new_nwd then
    -- Add the player to the new network's player set
    new_nwd.players_set[player_table.player_index] = true
    debugger.info("Added player index " .. tostring(player_table.player_index) .. " to network ID " .. tostring(new_nwd.id))
    player_table.network = new_network
    if not new_nwd.history_timer then
      new_nwd.history_timer = tick_counter.new()
    end
    new_nwd.history_timer:reset() -- Set history timer to 0
  end
end

--- Remove all references to this player
--- @param player_index uint The player index to remove
function network_data.remove_player_index(player_index)
  for _, networkdata in pairs(storage.networks) do
    local player_table = player_data.get_player_table(player_index)
    network_data.remove_player_index_from_networkdata(networkdata, player_table)
  end
end

--- Remove all references to this player
--- @param networkdata LINetworkData|nil The network data to remove the player from
--- @param player_table PlayerData|nil The player's data table, if any
function network_data.remove_player_index_from_networkdata(networkdata, player_table)
  if networkdata and player_table then
    if networkdata.players_set then
      networkdata.players_set[player_table.player_index] = nil
    end
    player_table.network = nil
    debugger.info("Removed player index " .. tostring(player_table.player_index) .. " from network ID " .. tostring(networkdata.id))
  else
    debugger.error("[remove_player_index_from_networkdata: Need both networkdata and player_table")
  end
end

--- Remove a network from storage, if it exists
---@param network_id number The network to remove
function network_data.remove_network(network_id)
  -- Remove the network from storage
  storage.networks[network_id] = nil
  return true
end

-- If the setting "li-show-all-networks" is false, purge networks that are not currently observed by any player
---@return boolean True if any networks were purged, false otherwise
function network_data.purge_unobserved_networks()
  local purged = false
  if global_data.purge_nonplayer_networks() then
    for network_id, networkdata in pairs(storage.networks) do
      if network_data.players_in_network(networkdata) == 0 then
        -- Remove the network data if it has no players
        network_data.remove_network(network_id)
        purged = true
      end
    end
  end
  return purged
end

--- Return the number of players currently observing this network
---@param networkdata LINetworkData|nil The network data to check
function network_data.players_in_network(networkdata)
  if not networkdata or not networkdata.players_set then
    return 0
  end
  return table_size(networkdata.players_set)
end

-- Get the LuaLogisticNetwork object for a given network data
---@param networkdata LINetworkData The network data to get the LuaLogisticNetwork
---@return LuaLogisticNetwork|nil
function network_data.get_LuaNetwork(networkdata)
  local force = game.forces[networkdata.force_name]
  if not force then return nil end

  local networks = force.logistic_networks[networkdata.surface] -- surface object as key
  if not networks then return nil end

  for _, nw in pairs(networks) do
    if nw.network_id == networkdata.id then
      return nw
    end
  end
  return nil
end

-- Return the next network to background scan, if any
---@return LINetworkData|nil The next network to scan, or nil if none available
function network_data.get_next_background_network()
  if global_data.background_refresh_interval_ticks() == 0 then
    return nil -- Background refresh is disabled
  end
  -- Only refresh networks that have not been refreshed for at least refresh-interval
  local last_tick = game.tick - global_data.background_refresh_interval_ticks()
  local list = {}
  if storage.networks then
    for _, networkdata in pairs(storage.networks) do
      if networkdata and networkdata.players_set then
        -- Check if the network still exists - might have been removed!
        local nw = network_data.get_LuaNetwork(networkdata)
        if not nw or not nw.valid then
          -- The network no longer exists, so remove it from storage
          network_data.remove_network(networkdata.id)
        elseif networkdata.last_scanned_tick < last_tick then
          -- This network has no active players, so it can be scanned in the background
          list[#list+1] = networkdata
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
  table.sort(list, function(a,b) return (a.last_scanned_tick or 0) < (b.last_scanned_tick or 0) end)

  if #list > 0 then
    -- Return the first network in the sorted list
    return list[1]
  else
    return nil -- No background networks available
  end
end

-- Return the next network to background scan, if any
---@return LINetworkData|nil The next network to scan, or nil if none available
function network_data.get_next_player_network()
  local list = {}
  if storage.networks then
    for _, networkdata in pairs(storage.networks) do
      if networkdata and networkdata.players_set then
        -- Check if the network still exists - might have been removed!
        local nw = network_data.get_LuaNetwork(networkdata)
        if not nw or not nw.valid then
          -- The network no longer exists, so remove it from storage
          network_data.remove_network(networkdata.id)
        elseif network_data.players_in_network(networkdata) > 0 then
          -- Check if any of the players have their bots window open
          if player_data.players_show_main_window(networkdata.players_set) then
            -- Addadd it to the candidate list
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
  table.sort(list, function(a,b) return (a.last_scanned_tick or 0) < (b.last_scanned_tick or 0) end)

  if #list > 0 then
    -- Return the first network in the sorted list
    return list[1]
  else
    return nil -- No player networks available
  end
end

---@param networkdata LINetworkData|nil The network data that has finished updating
function network_data.finished_scanning_network(networkdata)
  if networkdata then
    networkdata.last_scanned_tick = game.tick
  end
end

---@return {suggestions: number, undersupplies: number} The total number of suggestions across all networks
function network_data.get_total_suggestions_and_undersupply()
  local num_sug = 0
  local num_us = 0
  if storage.networks then
    for _, networkdata in pairs(storage.networks) do
      if networkdata and networkdata.suggestions then
        local undersupply = networkdata.suggestions:get_cached_list("undersupply")
        if undersupply then
          num_us = num_us + table_size(undersupply)
        end
        for _, suggestion in pairs(networkdata.suggestions:get_suggestions()) do
          if suggestion then
            num_sug = num_sug + 1
          end
        end
      end
    end
  end
  return {suggestions = num_sug, undersupplies = num_us}
end

---@param networkdata LINetworkData The network 
---@param storages LuaEntity[] -- The list of storage entities to add to the ignore list
function network_data.add_storages_to_ignorelist_for_filter_mismatch(networkdata, storages)
  if not networkdata or not storages or type(storages) ~= "table" then
    return
  end
  for _, item in pairs(storages) do
    if item and item.valid then
      local ID = item.unit_number
      if ID then
        networkdata.ignored_storages_for_mismatch[ID] = true
      end
    end
  end
end

---@param networkdata? LINetworkData The network
---@param iq ItemQuality The item quality to add to the ignore list
function network_data.add_item_to_ignorelist_for_undersupply(networkdata, iq)
  if not networkdata or not iq then
    return
  end
  -- The list is a table<string>, which allows O(1) lookups
  networkdata.ignored_items_for_undersupply[utils.get_ItemQuality_key(iq)] = true
end


return network_data