--- Shows a row of the most in-demand items where demand isn't met

local player_data = require("scripts.player-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local mini_button = require("scripts.mainwin.mini_button")

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
      function(pt) return not player_data.is_undersupply_paused(pt) end
    )
  end
end

--- Update the start/stop button appearance based on current state
--- @param player_table PlayerData The player's data table
function undersupply_row.update_pause_button(player_table)
  -- Update button appearance to reflect current state
  if player_table and player_table.ui then
    local element = player_table.ui.undersupply_control
    local is_paused = player_data.is_undersupply_paused(player_table)
    mini_button.update_paused(element, is_paused)
  end
end

return undersupply_row