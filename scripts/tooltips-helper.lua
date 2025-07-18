-- Helped functions to format complex tooltips consistently

local tooltips_helper = {}

local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")
local Cache = require("scripts.cache")
-- Cache for surface names to avoid repeated string concatenation
local surface_cache = Cache.new(function(surface_name) return "[space-location=" .. surface_name .. "]" end)

-- Network ID (Dynamic or Fixed)
function tooltips_helper.add_networkid_tip(tip, network_id, is_fixed)
  local network_id_tip
  if is_fixed then
    network_id_tip = {"network-row.network-id-tooltip", network_id, {"network-row.network-id-fixed-tooltip"}}
  else
    network_id_tip = {"network-row.network-id-tooltip", network_id, {"network-row.network-id-dynamic-tooltip"}}
  end

  -- Handle empty tip case
  if not tip or (type(tip) == "table" and #tip == 0) or tip == "" then
    return network_id_tip
  else
    return {"", tip, "\n", network_id_tip}
  end
end

--- Located on: (Planet)
function tooltips_helper.add_network_surface_tip(tip, network)
  if not network or not network.cells or #network.cells == 0 then
    return tip
  end

  -- If the network has cells, get the first cell's surface
  local cell = network.cells[1]
  if cell and cell.valid and cell.owner and cell.owner.valid then
    local surface = cell.owner.surface
    if surface and surface.valid then
      local sprite = surface_cache:get(surface.name)
      tip = {"", tip, "\n", {"network-row.network-id-surface-tooltip", sprite}}
    end
  end
  return tip
end

-- Add an empty line to the tooltip
function tooltips_helper.add_empty_line(tip)
  if not tip or #tip == 0 then
    return {"\n"}
  end
  return {"", tip, "\n"}
end

-- Idle: X of Y [item=logistic-robot]
function tooltips_helper.add_bots_idle_and_total_tip(tip, network, idle_count, total_count)
  if not network or not network.cells or #network.cells == 0 then
    return tip
  end

  return {"", tip, "\n", {"controller-gui.idle-total-count", idle_count, total_count, sprite}}
end

-- History data: Active for <time>, Paused, or Disabled in settings
function tooltips_helper.add_network_history_tip(tip, player_table)
  if not player_table or not player_table.history_timer then
    return tip
  end

  if player_table.settings.show_history then
    local tickstr
    if player_data.is_paused(player_table) then
      tickstr =  flib_format.time(player_table.history_timer:time_since_paused(), false)
      tip = {"", tip, "\n", {"network-row.network-id-history", {"network-row.paused-for", tickstr}}}
    else
      if player_table.history_timer then
        tickstr = flib_format.time(player_table.history_timer:total_unpaused(), false)
      else
        tickstr = "n/a"
      end
      tip = {"", tip, "\n", {"network-row.network-id-history", {"network-row.network-id-history-collected-for", tickstr}}}
    end
  else
    tip = {"", tip, "\n", {"network-row.network-id-history", {"network-row.network-id-history-disabled"}}}
  end
  return tip
end

return tooltips_helper