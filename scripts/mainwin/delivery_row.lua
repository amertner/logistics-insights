-- Delivery row functionality for the logistics insights GUI
-- Handles real-time delivery tracking and display

local delivery_row = {}
local network_data = require("scripts.network-data")

local sorted_item_row = require("scripts.mainwin.sorted_item_row")

--- Add a delivery row to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
function delivery_row.add(player_table, gui_table)
  sorted_item_row.add(player_table, gui_table, "deliveries-row", "delivery", true)
  return 1
end

--- Update the delivery row with current data
--- @param player_table PlayerData The player's data table
--- @param clearing boolean Whether this update is due to clearing history
function delivery_row.update(player_table, clearing)
  local networkdata = network_data.get_networkdata(player_table.network)
  if networkdata then
    local clicktip
    if player_table.settings.pause_for_bots then
      clicktip = {"bots-gui.show-location-and-pause-tooltip"}
    else
      clicktip = {"bots-gui.show-location-tooltip"}
    end
    sorted_item_row.update(
      player_table,
      "deliveries-row",
      networkdata.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count",
      clearing,
      clicktip
    )
  else
    -- If no network data, clear the delivery row
    sorted_item_row.clear_cells(player_table, "deliveries-row")
  end
end

return delivery_row
