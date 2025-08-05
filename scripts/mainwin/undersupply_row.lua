--- Shows a row of the most in-demand items where demand isn't met

local player_data = require("scripts.player-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local mini_button = require("scripts.mainwin.mini_button")
local pause_manager = require("scripts.pause-manager")

local undersupply_row = {}
local ROW_TITLE = "undersupply-row"

---@param player_table PlayerData The player's data table
---@param gui_table LuaGuiElement The GUI table to add the row to
function undersupply_row.add(player_table, gui_table)
  if player_table.settings.show_undersupply then
    -- Add a standard sorted item row, with pause/start button
    sorted_item_row.add(player_table, gui_table, ROW_TITLE, "undersupply", false)
  end
end

---@param player_table PlayerData The player's data table
function undersupply_row.update(player_table, clearing)
  if storage.undersupply == nil then
    storage.undersupply = {}
  end
  if player_table and player_table.settings.show_undersupply then
    sorted_item_row.update(
      player_table,
      ROW_TITLE,
      storage.undersupply,
      function(a, b) return a.shortage > b.shortage end,
      "shortage",
      clearing,
      function(pt) return pause_manager.is_running(player_table.paused_items, "undersupply") end
    )
  end
end

return undersupply_row