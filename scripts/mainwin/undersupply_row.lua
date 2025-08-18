--- Shows a row of the most in-demand items where demand isn't met

local player_data = require("scripts.player-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local mini_button = require("scripts.mainwin.mini_button")
local capability_manager = require("scripts.capability-manager")
local suggestions   = require("scripts.suggestions")

---@class undersupply_row
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
---@param clearing? boolean Whether we are updating because history was just cleared
function undersupply_row.update(player_table, clearing)
  if not player_table then return end
  if not player_table.settings.show_undersupply then return end
  local in_demand = player_table.suggestions:get_cached_list("undersupply")
  if in_demand then
    sorted_item_row.update(
      player_table,
      ROW_TITLE,
      in_demand or {},
      function(a, b) return a.shortage > b.shortage end,
      "shortage",
      clearing or false,
      function(pt) return capability_manager.is_active(player_table, "undersupply") end,
      {"undersupply-row.show-location-tooltip"}
    )
  else
    sorted_item_row.clear_cells(player_table, ROW_TITLE)
  end
end

return undersupply_row