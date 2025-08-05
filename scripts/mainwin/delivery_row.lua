-- Delivery row functionality for the logistics insights GUI
-- Handles real-time delivery tracking and display

local delivery_row = {}

local sorted_item_row = require("scripts.mainwin.sorted_item_row")

--- Add a delivery row to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
function delivery_row.add(player_table, gui_table)
  if player_table.settings.show_delivering then
    sorted_item_row.add(player_table, gui_table, "deliveries-row", "delivery", true)
  end
end

--- Update the delivery row with current data
--- @param player_table PlayerData The player's data table
--- @param clearing boolean Whether this update is due to clearing history
function delivery_row.update(player_table, clearing)
  if player_table.settings.show_delivering then
    sorted_item_row.update(
      player_table,
      "deliveries-row",
      storage.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count",
      clearing,
      function(pt) return true end
    )
  end
end

return delivery_row
