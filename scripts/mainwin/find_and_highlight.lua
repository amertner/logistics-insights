--- Functions to find items to highlight on the map when clicked

local find_and_highlight = {}

local utils = require("scripts.utils")
local game_state = require("scripts.game-state")
local ResultLocation = require("scripts.result-location")

---@class ViewData
---@field items LuaEntity[]|nil List of entities to highlight
---@field item LuaEntity|nil Random selected entity to focus on
---@field follow boolean Whether to follow/focus on the selected item

--- Find charging robots in the given cell list
--- @param player_table PlayerData The player's data table
--- @param cell_list LuaLogisticCell[] List of logistic cells to search
--- @return LuaEntity[]|nil List of charging robots or nil if none found
local function find_charging_robots(player_table, cell_list)
  if not cell_list or #cell_list == 0 then
    return nil
  end
  local bot_list = {}
  for _, cell in pairs(cell_list) do
    if cell and cell.valid and cell.charging_robots then
      for _, bot in pairs(cell.charging_robots) do
        table.insert(bot_list, bot)
      end
    end
  end
  return bot_list
end

--- Find robots waiting to charge in the given cell list
--- @param player_table PlayerData The player's data table
--- @param cell_list LuaLogisticCell[] List of logistic cells to search
--- @return LuaEntity[]|nil List of waiting robots or nil if none found
local function find_waiting_to_charge_robots(player_table, cell_list)
  if not cell_list or #cell_list == 0 then
    return nil
  end
  local bot_list = {}
  for _, cell in pairs(cell_list) do
    if cell and cell.valid and cell.to_charge_robots then
      for _, bot in pairs(cell.to_charge_robots) do
        table.insert(bot_list, bot)
      end
    end
  end
  return bot_list
end

--- Get item list and focus data for stationary items
--- @param item_list LuaEntity[] List of entities
--- @return ViewData View data with items and random selection
local function get_item_list_and_focus(item_list)
  local rando = utils.get_random(item_list)
  return {items = item_list, item = rando, follow = false}
end

--- Get item list and focus data for mobile items (with following)
--- @param item_list LuaEntity[] List of entities
--- @return ViewData View data with items and random selection (with follow enabled)
local function get_item_list_and_focus_mobile(item_list)
  local rando = utils.get_random(item_list)
  if rando then
    return {items = item_list, item = rando, follow = true}
  else
    return {items = item_list, item = nil, follow = false}
  end
end

--- Get item list and focus data using a find function
--- @param player_table PlayerData The player's data table
--- @param find_fn function Function to find items in cells
--- @return ViewData View data with found items
local function get_item_list_and_focus_from_player_table(player_table, find_fn)
  if find_fn == nil or player_table == nil or player_table.network == nil or player_table.network.cells == nil then
    return {items = nil, item = nil, follow = false}
  end
  local filtered_list = find_fn(player_table, player_table.network.cells)
  if filtered_list == nil or #filtered_list == 0 then
    return {items = nil, item = nil, follow = false}
  else
    return get_item_list_and_focus_mobile(filtered_list)
  end
end

--- Get owner entities from a list of items
--- @param item_list LuaEntity[] List of (logistic cells)
--- @return ViewData View data with owner entities
local function get_item_list_and_focus_owner(item_list)
  local ownerlist = {}
  for _, item in pairs(item_list) do
    if item and item.valid then
      ---@diagnostic disable-next-line: undefined-field
      local owner = item.owner
      if owner then
        table.insert(ownerlist, owner)
      end
    end
  end
  return get_item_list_and_focus(ownerlist)
end

--- Filter bot list by order type (deliver/pickup)
--- @param bot_list LuaEntity[] List of robot entities
--- @param order_type defines.robot_order_type The order type to filter by
--- @return ViewData View data with filtered bots
local function get_item_list_and_focus_from_botlist(bot_list, order_type)
  if not bot_list or #bot_list == 0 then
    return {items = nil, item = nil, follow = false}
  end
  local filtered_list = {}
  for _, bot in pairs(bot_list) do
    if bot and bot.valid and table_size(bot.robot_order_queue) > 0 then
     if bot.robot_order_queue[1].type == order_type then
      table.insert(filtered_list, bot)
     end
    end
  end
  return get_item_list_and_focus_mobile(filtered_list)
end

--- Exclude roboports from item list
--- @param item_list LuaEntity[] List of entities
--- @return ViewData View data with non-roboport entities
local function get_item_list_and_focus_exclude_roboports(item_list)
  local list = {}
  for _, item in pairs(item_list) do
    if item and item.valid and item.type ~= "roboport" then
      table.insert(list, item)
    end
  end
  return get_item_list_and_focus(list)
end

---@type table<string, fun(pd: PlayerData): ViewData>
local get_list_function = {
  -- Activity row buttons
  ["logistics-insights-logistic-robot-total"] = function(pd)
    return get_item_list_and_focus_mobile(pd.network.logistic_robots)
  end,
  ["logistics-insights-charging-robot"] = function(pd)
    return get_item_list_and_focus_from_player_table(pd, find_charging_robots)
  end,
  ["logistics-insights-waiting-for-charge-robot"] = function(pd)
    return get_item_list_and_focus_from_player_table(pd, find_waiting_to_charge_robots)
  end,
  ["logistics-insights-delivering"] = function(pd)
    return get_item_list_and_focus_from_botlist(pd.network.logistic_robots, defines.robot_order_type.deliver)
  end,
  ["logistics-insights-picking"] = function(pd)
    return get_item_list_and_focus_from_botlist(pd.network.logistic_robots, defines.robot_order_type.pickup)
  end,
  -- Network row buttons
  ["logistics-insights-roboports"] = function(pd)
    return get_item_list_and_focus_owner(pd.network.cells)
  end,
  ["logistics-insights-requesters"] = function(pd)
    return get_item_list_and_focus(pd.network.requesters)
  end,
  ["logistics-insights-logistics_bots"] = function(pd)
    return get_item_list_and_focus_mobile(pd.network.logistic_robots)
  end,
  ["logistics-insights-providers"] = function(pd)
    return get_item_list_and_focus_exclude_roboports(pd.network.providers)
  end,
  ["logistics-insights-storages"] = function(pd)
    return get_item_list_and_focus(pd.network.storages)
  end,
}

--- Highlight locations on the map when GUI elements are clicked
--- @param player LuaPlayer The player viewing the map
--- @param player_table PlayerData|nil The player's data table
--- @param element LuaGuiElement The sprite-button that was clicked
--- @param focus_on_element boolean Whether to focus on the selected element
function find_and_highlight.highlight_locations_on_map(player, player_table, element, focus_on_element)
  local fn = get_list_function[element.name]
  if not fn then
    return
  end

  if player_table == nil or player_table.network == nil then
    return -- Fix crash when outside of network
  end

  local viewdata = fn(player_table)
  if viewdata == nil or viewdata.item == nil then
    return
  end

  if viewdata.follow and player.mod_settings["li-pause-for-bots"].value then
    game_state.freeze_game()
  end
  local toview = {
    position = viewdata.item.position,
    surface = viewdata.item.surface.name,
    zoom = 0.8,
    items = viewdata.items,
  }
  ResultLocation.open(player, toview, focus_on_element)
end

--- Clear all markers and selected items from the map
--- @param player LuaPlayer The player viewing the map
function find_and_highlight.clear_markers(player)
  ResultLocation.clear_markers(player)
end

return find_and_highlight