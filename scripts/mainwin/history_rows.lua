-- History rows functionality for the logistics insights GUI
-- Handles historical delivery data display (totals, distance carried and longest trip)

local history_rows = {}

local network_data = require("scripts.network-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local ResultLocation = require("scripts.result-location")
local utils = require("scripts.utils")

local sort_by_count_desc = function(a, b) return a.count > b.count end
local sort_by_dist_sum_desc = function(a, b) return a.dist_sum > b.dist_sum end
local sort_by_top_dist_desc = function(a, b) return a.top_dist > b.top_dist end

--- Only items with a known trip distance belong in the distance carried row
--- @param delivery_history table<string, DeliveredItems>
--- @return table<string, DeliveredItems>
local function with_distance_carried(delivery_history)
  local entries = {}
  for key, entry in pairs(delivery_history) do
    if (entry.dist_sum or 0) > 0 then
      entries[key] = entry
    end
  end
  return entries
end

--- Only items with a trip to list belong in the longest trip row: one with a known distance,
--- to a destination not on the ignore list
--- @param delivery_history table<string, DeliveredItems>
--- @return table<string, DeliveredItems>
local function with_trip_distance(delivery_history)
  local entries = {}
  for key, entry in pairs(delivery_history) do
    if (entry.top_dist or 0) > 0 then
      entries[key] = entry
    end
  end
  return entries
end

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

function history_rows.update(player_table, clearing)
  local networkdata = network_data.get_networkdata(player_table.network)
  if player_table.settings.show_history then
    if  networkdata and networkdata.delivery_history then
      sorted_item_row.update(
        player_table,
        "totals-row",
        networkdata.delivery_history,
        sort_by_count_desc,
        "count",
        clearing,
        nil,
        networkdata.delivery_history_gen
      )

      -- Filtering allocates, so only do it when the history has changed since the row was drawn
      local distance_ui = player_table.ui["distance-row"]
      if not distance_ui or distance_ui.last_gen ~= networkdata.delivery_history_gen then
        sorted_item_row.update(
          player_table,
          "distance-row",
          with_distance_carried(networkdata.delivery_history),
          sort_by_dist_sum_desc,
          "dist_sum",
          clearing,
          nil,
          networkdata.delivery_history_gen
        )
      end

      -- Offer to ignore a trip only on the item whose trip is on the map
      local view = player_table.trip_view
      local shown_key = view and ResultLocation.is_shown(view.object_id) and view.key or ""
      local tip = {"item-row.maxdist-click-tip-1count", network_data.TOP_TRIPS}
      local function click_tip(entry)
        if utils.get_item_quality_key(entry.item_name, entry.quality_name or "normal") == shown_key then
          -- This item's trip is on the map, so say what clicking again does, and offer to ignore it
          local shown_tip = {"item-row.maxdist-click-tip-shown-1count", #(entry.top_trips or {})}
          return {"", shown_tip, "\n", {"item-row.maxdist-ignore-tip"}}
        end
        return tip
      end

      -- Filtering allocates, so only do it when the history, or which trip is shown, has changed
      local gen = (networkdata.delivery_history_gen or 0) .. "|" .. shown_key
      local ui = player_table.ui["maxdist-row"]
      if not ui or ui.last_gen ~= gen then
        sorted_item_row.update(
          player_table,
          "maxdist-row",
          with_trip_distance(networkdata.delivery_history),
          sort_by_top_dist_desc,
          "top_dist",
          clearing,
          click_tip,
          gen
        )
      end
    else
      sorted_item_row.clear_cells(player_table, "totals-row")
      sorted_item_row.clear_cells(player_table, "distance-row")
      sorted_item_row.clear_cells(player_table, "maxdist-row")
    end
  end
end

return history_rows