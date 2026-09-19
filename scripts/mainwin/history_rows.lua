-- History rows functionality for the logistics insights GUI
-- Handles historical delivery data display (totals, average ticks and longest haul)

local history_rows = {}

local network_data = require("scripts.network-data")
local sorted_item_row = require("scripts.mainwin.sorted_item_row")
local ResultLocation = require("scripts.result-location")
local utils = require("scripts.utils")

local sort_by_count_desc = function(a, b) return a.count > b.count end
local sort_by_avg_desc = function(a, b) return a.avg > b.avg end
local sort_by_top_dist_desc = function(a, b) return a.top_dist > b.top_dist end

--- Only items with a haul to list belong in the longest haul row: one with a known distance,
--- to a destination not on the ignore list
--- @param delivery_history table<string, DeliveredItems>
--- @return table<string, DeliveredItems>
local function with_haul_distance(delivery_history)
  local entries = {}
  for key, entry in pairs(delivery_history) do
    if (entry.top_dist or 0) > 0 then
      entries[key] = entry
    end
  end
  return entries
end

--- Add history rows to the GUI (totals, average ticks and longest haul)
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the rows to
function history_rows.add(player_table, gui_table)
  if player_table.settings.show_history then
    sorted_item_row.add(player_table, gui_table, "totals-row", "clear", false)
    sorted_item_row.add(player_table, gui_table, "avgticks-row", "ticks", false)
    sorted_item_row.add(player_table, gui_table, "maxdist-row", "haul", false)
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

      sorted_item_row.update(
        player_table,
        "avgticks-row",
        networkdata.delivery_history,
        sort_by_avg_desc,
        "avg",
        clearing,
        nil,
        networkdata.delivery_history_gen
      )

      -- Offer to ignore a haul only on the item whose haul is on the map
      local view = player_table.haul_view
      local shown_key = view and ResultLocation.is_shown(view.object_id) and view.key or ""
      local function click_tip(entry)
        if utils.get_item_quality_key(entry.item_name, entry.quality_name or "normal") == shown_key then
          return {"", {"item-row.maxdist-click-tip"}, "\n", {"item-row.maxdist-ignore-tip"}}
        end
        return {"item-row.maxdist-click-tip"}
      end

      -- Filtering allocates, so only do it when the history, or which haul is shown, has changed
      local gen = (networkdata.delivery_history_gen or 0) .. "|" .. shown_key
      local ui = player_table.ui["maxdist-row"]
      if not ui or ui.last_gen ~= gen then
        sorted_item_row.update(
          player_table,
          "maxdist-row",
          with_haul_distance(networkdata.delivery_history),
          sort_by_top_dist_desc,
          "top_dist",
          clearing,
          click_tip,
          gen
        )
      end
    else
      sorted_item_row.clear_cells(player_table, "totals-row")
      sorted_item_row.clear_cells(player_table, "avgticks-row")
      sorted_item_row.clear_cells(player_table, "maxdist-row")
    end
  end
end

return history_rows