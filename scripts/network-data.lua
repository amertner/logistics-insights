--- Manage storage of network data analysed by LI
local network_data = {}

local suggestions = require("scripts.suggestions")
local capability_manager = require("scripts.capability-manager")
local chunker = require("scripts.chunker")
local player_data = require("scripts.player-data")

-- Data stored for each network
---@class LINetworkData
---@field id number -- The unique ID of the network
---@field surface string -- The surface name where the network is located
---@field force_name string -- The force name of the network
---@field players number[] -- A list of player indexes that are active in this network
---@field cell_chunker Chunker -- Chunker for processing logistic cells
---@field bot_chunker Chunker -- Chunker for processing logistic bots
---@ -- Suggestions and undersupply data
---@field suggestions Suggestions -- The list of suggestions associated with this network
---@ -- Data capture fields
---@field last_active_tick number -- The last tick this network's data was updated
---@field last_accessed_tick number -- The last tick this network's data was accessed
---@field last_pass_bots_seen table<number, number> -- A list of bots seen in the last full pass
---@ -- Fields populated by analysing cells
---@field idle_bot_qualities QualityTable Quality of idle bots in roboports
---@field charging_bot_qualities QualityTable Quality of bots currently charging
---@field waiting_bot_qualities QualityTable Quality of bots waiting to charge
---@field roboport_qualities QualityTable Quality of roboports
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
  if not network or not network.network_id or not storage.networks then
    return nil -- No network ID or storage available
  end
  local networkdata = storage.networks[network.network_id]
  if not networkdata then
    return nil -- No data for this network
  else
    -- Update last-accessed
    networkdata.last_accessed_tick = game.tick
    networkdata.last_active_tick = game.tick
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
    networkdata.last_active_tick = game.tick
    return networkdata
  end
end

---@param network LuaLogisticNetwork|nil The network to create storage for
function network_data.create_networkdata(network)
  if not network or not storage.networks then
    return nil -- No network ID or storage available
  end

  -- Create a new network data entry if it doesn't exist
  if not storage.networks[network.network_id] then
    storage.networks[network.network_id] = {
      id = network.network_id,
      surface = network.cells[1].owner.surface.name or "",
      force_name = network.force.name or "",
      players = {},
      cell_chunker = chunker.new(),
      bot_chunker = chunker.new(),
      last_accessed_tick = game.tick,
      last_active_tick = game.tick,
      suggestions = suggestions.new(),
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
      total_bot_qualities = {}
    }
  end
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
  local nw = network_data.get_networkdata(network)
  if nw then
    nw.delivery_history = {} -- Clear the delivery history
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
      local has_network = (network ~= nil)
      capability_manager.set_reason(player_table, "delivery", "no_network", not has_network)
      capability_manager.set_reason(player_table, "activity", "no_network", not has_network)
      capability_manager.set_reason(player_table, "history", "no_network", not has_network)
      capability_manager.set_reason(player_table, "suggestions", "no_network", not has_network)
      capability_manager.set_reason(player_table, "undersupply", "no_network", not has_network)
      return false
    else
      player_table.network = network
      player_table.history_timer:reset() -- Reset the tick counter when network changes
      local has_network = (network ~= nil)
      capability_manager.set_reason(player_table, "delivery", "no_network", not has_network)
      capability_manager.set_reason(player_table, "activity", "no_network", not has_network)
      capability_manager.set_reason(player_table, "history", "no_network", not has_network)
      capability_manager.set_reason(player_table, "suggestions", "no_network", not has_network)
      capability_manager.set_reason(player_table, "undersupply", "no_network", not has_network)

      network_data.player_changed_networks(player_table, old_network_id, new_network_id)
      return true
    end
  else
    return false
  end
end

--- Call this to update the list of players active in a network
---@param player_table PlayerData The player's data table
---@param old_network_id uint|nil The old network ID, if any
---@param new_network_id uint|nil The new network ID, if any
function network_data.player_changed_networks(player_table, old_network_id, new_network_id)
  if not player_table then
    return
  end
  local old_nw = network_data.get_networkdata_fromid(old_network_id)
  if old_nw and old_network_id then
    table.remove(old_nw.players, player_table.player_index)
    -- If the old network has no players left, potentially remove it
    if old_nw.players and #old_nw.players == 0 then
      if not settings.global["li-show-all-networks"].value then
        storage.networks[old_network_id] = nil
      end
    end
  end
  local new_nw = network_data.get_networkdata_fromid(new_network_id)
  if new_nw then
    table.insert(new_nw.players, player_table.player_index)
  end
end

--- Remove a network from storage, if it exists
---@param network_id number The network to remove
function network_data.remove_network(network_id)
  -- Remove the network from storage
  storage.networks[network_id] = nil
end

-- If the setting "li-show-all-networks" is false, purge networks that are not currently observed by any player
---@return boolean True if any networks were purged, false otherwise
function network_data.purge_unobserved_networks()
  local purged = false
  if not settings.global["li-show-all-networks"].value then
    for network_id, networkdata in pairs(storage.networks) do
      if not networkdata.players or #networkdata.players == 0 then
        -- Remove the network data if it has no players
        network_data.remove_network(network_id)
        purged = true
      end
    end
  end
  return purged
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
  -- Only refresh networks that have not been refreshed for at least refresh-interval
  local last_tick = game.tick - settings.global["li-background-refresh-interval"].value * 60
  local list = {}
  if storage.networks then
    for _, nw in pairs(storage.networks) do
      if nw and nw.players and #nw.players == 0 and nw.last_active_tick < last_tick then
        -- This network has no active players, so it can be scanned in the background
        -- Add it to the list for background scanning
        list[#list+1] = nw
      end
    end
  else
    return nil -- No networks available
  end

  if #list == 0 then
    return nil -- No networks need a background scan
  end
  -- Sort by last active tick, so the oldest networks are scanned first
  table.sort(list, function(a,b) return (a.last_active_tick or 0) < (b.last_active_tick or 0) end)

  if #list > 0 then
    -- Return the first network in the sorted list
    return list[1]
  else
    return nil -- No background networks available
  end
end



return network_data