-- History rows functionality for the logistics insights GUI
-- Handles historical delivery data display (totals and average ticks)

local history_rows = {}

local network_data = require("scripts.network-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")

--- Add history rows to the GUI (totals and average ticks)
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the rows to
function history_rows.add(player_table, gui_table)
  if player_table.settings.show_history then
    sorted_item_row.add(player_table, gui_table, "totals-row", "clear", false)
    sorted_item_row.add(player_table, gui_table, "avgticks-row", "ticks", false)
    return 2
  end
  return 0
end

function history_rows.update(player_table, clearing)
  local networkdata = network_data.get_networkdata(player_table.network)
  if player_table.settings.show_history then
    if  networkdata and networkdata.delivery_history then
      sorted_item_row.update(
        player_table,
        "totals-row",
        networkdata.delivery_history,
        function(a, b) return a.count > b.count end,
        "count",
        clearing,
        nil
      )

      sorted_item_row.update(
        player_table,
        "avgticks-row",
        networkdata.delivery_history,
        function(a, b) return a.avg > b.avg end,
        "avg",
        clearing,
        nil
      )
    else
      sorted_item_row.clear_cells(player_table, "totals-row")
      sorted_item_row.clear_cells(player_table, "avgticks-row")
    end
  end
end

return history_rows