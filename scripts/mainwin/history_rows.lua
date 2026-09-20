-- History rows functionality for the logistics insights GUI
-- Handles historical delivery data display (totals, distance carried and longest trip)

local history_rows = {}

local network_data = require("scripts.network-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local ResultLocation = require("scripts.result-location")
local utils = require("scripts.utils")
local trip_view = require("scripts.trip-view")

-- History recorded before trip distance was tracked has no distance fields at all, and an item can
-- be delivered without one ever being worked out, so both distance rows sort over entries that may
-- have nothing to show. They sort last and the row stops at the first of them, which leaves the
-- same items on screen as filtering the list first did, without copying it every update
local sort_by_count_desc = function(a, b) return a.count > b.count end
local sort_by_dist_sum_desc = function(a, b) return (a.dist_sum or 0) > (b.dist_sum or 0) end
local sort_by_top_dist_desc = function(a, b) return (a.top_dist or 0) > (b.top_dist or 0) end

--- Add history rows to the GUI (totals, distance carried and longest trip)
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the rows to
function history_rows.add(player_table, gui_table)
  if player_table.settings.show_history then
    sorted_item_row.add(player_table, gui_table, "totals-row", "clear", false)
    sorted_item_row.add(player_table, gui_table, "distance-row", "distance", false)
    sorted_item_row.add(player_table, gui_table, "maxdist-row", "trip", false)
    return 3
  end
  return 0
end

function history_rows.update(player_table)
  local networkdata = network_data.get_networkdata(player_table.network)
  if player_table.settings.show_history then
    if  networkdata and networkdata.delivery_history then
      local history = networkdata.delivery_history
      local history_gen = networkdata.delivery_history_gen
      sorted_item_row.update(player_table, "totals-row", history, sort_by_count_desc, "count", nil, history_gen)
      sorted_item_row.update(player_table, "distance-row", history, sort_by_dist_sum_desc, "dist_sum", nil, history_gen)

      -- Offer to ignore a trip only on the item whose trip is on the map, so which trip is shown
      -- is part of what the row was drawn from
      local shown_key = trip_view.shown(player_table, networkdata, ResultLocation.is_shown) or ""
      local gen = (history_gen or 0) .. "|" .. shown_key
      local ui = player_table.ui["maxdist-row"]
      if not ui or ui.last_gen ~= gen then
        -- Only worth building the tooltips when the row is actually being redrawn
        local tip = {"item-row.maxdist-click-tip-1count", network_data.TOP_TRIPS}
        local function click_tip(entry)
          if utils.get_item_quality_key(entry.item_name, entry.quality_name or "normal") == shown_key then
            -- This item's trip is on the map, so say what clicking again does, and offer to ignore it
            local shown_tip = {"item-row.maxdist-click-tip-shown-1count", #(entry.top_trips or {})}
            return {"", shown_tip, "\n", {"item-row.maxdist-ignore-tip"}}
          end
          return tip
        end
        sorted_item_row.update(player_table, "maxdist-row", history, sort_by_top_dist_desc, "top_dist",
          click_tip, gen)
      end
    else
      sorted_item_row.clear_cells(player_table, "totals-row")
      sorted_item_row.clear_cells(player_table, "distance-row")
      sorted_item_row.clear_cells(player_table, "maxdist-row")
    end
  end
end

return history_rows