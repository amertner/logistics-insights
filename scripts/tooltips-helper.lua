-- Helped functions to format complex tooltips consistently

local tooltips_helper = {}

local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")
local pause_manager = require("scripts.pause-manager")
local Cache = require("scripts.cache")
-- Cache for surface names to avoid repeated string concatenation
local surface_cache = Cache.new(function(surface_name) return "[space-location=" .. surface_name .. "]" end)

-- Network ID (Dynamic or Fixed)
---@param tip table<LocalisedString> Existing tooltip content
---@param network_id number The network ID to display
---@param is_fixed boolean Whether the network is fixed or dynamic
---@return table<LocalisedString> The formatted tooltip
function tooltips_helper.add_networkid_tip(tip, network_id, is_fixed)
  local network_id_tip
  if is_fixed then
    network_id_tip = {"network-row.network-id-tooltip-1ID-2Status", network_id, {"network-row.network-id-fixed-tooltip"}}
  else
    network_id_tip = {"network-row.network-id-tooltip-1ID-2Status", network_id, {"network-row.network-id-dynamic-tooltip"}}
  end

  -- Handle empty tip case
  if not tip or (type(tip) == "table" and #tip == 0) or tip == "" then
    return network_id_tip
  else
    return {"", tip, "\n", network_id_tip}
  end
end

--- Located on: (Planet)
---@param tip table<LocalisedString> Existing tooltip content
---@param network LuaLogisticNetwork|nil The logistics network to get surface info from
---@return table<LocalisedString> The formatted tooltip with surface information
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
      local lname
      if surface and surface.valid and surface.planet and surface.planet.prototype then
        -- Use the planet's localised name for the tooltip
        lname = surface.planet.prototype.localised_name
      else
        lname = surface.name
      end
      tip = {"", tip, "\n", {"network-row.network-id-surface-tooltip-1icon-2name", sprite, lname}}
    end
  end
  return tip
end

-- Add an empty line to the tooltip
---@param tip table<LocalisedString> Existing tooltip content
---@return table<LocalisedString> The tooltip with an empty line added
function tooltips_helper.add_empty_line(tip)
  if not tip or #tip == 0 then
    return {"\n"}
  end
  return {"", tip, "\n"}
end

-- Idle: X of Y [item=logistic-robot]
---@param tip table<LocalisedString> Existing tooltip content
---@param network LuaLogisticNetwork|nil The logistics network
---@param idle_count number Number of idle robots
---@param total_count number Total number of robots
---@return table<LocalisedString> The formatted tooltip
function tooltips_helper.add_bots_idle_and_total_tip(tip, network, idle_count, total_count)
  if not network or not network.cells or #network.cells == 0 then
    return tip
  end

  return {"", tip, "\n", {"controller-gui.idle-total-count-1idle-2total", idle_count, total_count}}
end

-- History data: Active for <time>, Paused, or Disabled in settings
---@param tip table<LocalisedString> Existing tooltip content
---@param player_table PlayerData The player's data table
---@return table<LocalisedString> The formatted tooltip with history information
function tooltips_helper.add_network_history_tip(tip, player_table)
  if not player_table or not player_table.history_timer then
    return tip
  end

  if player_table.settings.show_history then
    local tickstr
    if pause_manager.is_paused(player_table.paused_items, "history") then
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

---@param player_table PlayerData The player's data table
---@param formatstr string The format string for the tooltip
---@param count number The count to display
---@param quality_table table<string, number> Table of quality names to counts
---@return table<LocalisedString> The formatted tooltip with count and quality information
function tooltips_helper.create_count_with_qualities_tip(player_table, formatstr, count, quality_table)
  -- Line 1: Show count string
  local tip = { "", {formatstr, count}, "\n" }
  -- Line 2: Show quality counts
  tip = tooltips_helper.get_quality_tooltip_line(tip, player_table, quality_table)
  return tip
end

-- Return a formatted tooltip based on the quality_counts, to be used in a tooltip
-- formatname is the format string for the tooltip, e.g. "network-row.logistic-robot-quality-tooltip-1quality-2count"
-- quality_counts is a table with quality names as keys and their counts as values
-- separator is a string to separate different qualities in the tooltip
-- if include_empty is true, the tip will include qualities with zero count
---@param formatname string The format string for individual quality entries
---@param quality_table table<string, number> Table of quality names to counts
---@param item_separator? string Separator between quality entries (default: ", ")
---@param include_empty? boolean Whether to include qualities with zero count
---@return table<LocalisedString> The formatted quality tooltip or {""} if no data
local function getqualitytip(formatname, quality_table, item_separator, include_empty)
  local tip = {""}
  if not formatname or not quality_table or not prototypes.quality then
    return tip
  end

  local separator = ""
  -- Iterate over all qualities
  local quality = prototypes.quality.normal
  while quality do
    local amount = quality_table[quality.name] or 0
    if include_empty or amount > 0 then
      -- Use coloured quality names to show bot qualities
      tip = {"", tip, separator, {formatname, quality.name, amount}}
      separator = item_separator or ", "
    end
    -- Make sure we iterate over the qualities in quality order
    quality = quality.next
  end

  return tip
end

-- Return a whole line for all qualities
---@param tip table<LocalisedString> Existing tooltip content
---@param player_table PlayerData The player's data table
---@param quality_table table<string, number> Table of quality names to counts
---@param newline? boolean Whether to add a newline at the end
---@param formatstr? string Optional format string to wrap the quality tip
---@return table<LocalisedString> The tooltip with quality information added
function tooltips_helper.get_quality_tooltip_line(tip, player_table, quality_table, newline, formatstr)
  if player_table.settings.gather_quality_data and prototypes.quality then
    local quality_tip = getqualitytip("network-row.quality-tooltip-1quality-2count", quality_table, "  ", true)
    if formatstr then
      tip = {"", tip, {formatstr, quality_tip}}
    else
      --tip = {"", tip, {"quality-item-format.no-quality-item-format", quality_tip}}
      tip = {"", tip, quality_tip}
    end
    if newline then
      tip = {"", tip, "\n"}
    end
  end
  return tip
end

return tooltips_helper