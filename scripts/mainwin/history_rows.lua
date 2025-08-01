-- History rows functionality for the logistics insights GUI
-- Handles historical delivery data display (totals and average ticks)

local history_rows = {}

local player_data = require("scripts.player-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")

--- Add history rows to the GUI (totals and average ticks)
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the rows to
function history_rows.add(player_table, gui_table)
 sorted_item_row.add(player_table, gui_table, "totals-row", "clear", false)
 sorted_item_row.add(player_table, gui_table, "avgticks-row", nil, false)
end

function history_rows.update(player_table, clearing)
  if player_table.settings.show_history and storage.delivery_history then
    sorted_item_row.update(
      player_table,
      "totals-row",
      storage.delivery_history,
      function(a, b) return a.count > b.count end,
      "count",
      clearing
    )

    sorted_item_row.update(
      player_table,
      "avgticks-row",
      storage.delivery_history,
      function(a, b) return a.avg > b.avg end,
      "avg",
      clearing
    )
  end
end

return history_rows