--- Manage storage of network data analysed by LI
local network_data = {}

-- Data stored for each network
---@class LINetworkData
---@field id number -- The unique ID of the network
---@field surface string -- The surface name where the network is located
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
      last_accessed_tick = game.tick,
      last_active_tick = game.tick,
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

---@param player_table PlayerData The player data table to update
---@param old_network_id number|nil|boolean The previous network ID
---@param new_network_id number|nil|boolean The new network ID
function network_data.network_changed(player_table, old_network_id, new_network_id)
  -- If the network has changed, reset the network data
  if old_network_id and old_network_id > 0 then
    -- Clear the old network data. One day, we may want to keep this data, but not needed atm
    -- storage.networks[old_network_id] = nil
  end
end

return network_data