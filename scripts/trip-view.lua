--- Which of an item's longest trips a click should show.
---
--- A click that would redraw exactly what is already on the map moves on to the next trip
--- instead, so no click is ever wasted. Pressing the other mouse button shows the other end of
--- the same trip, so a delivery can still be paired with where it came from.
local trip_view = {}

--- Which trip a click should show
---@param view {index: integer, on_start: boolean|nil}|nil The trip on the map, nil if none is
---@param count integer How many longest trips the item has
---@param on_start boolean Which end this click wants to look at
---@param default integer Which trip to show when none of this item's are on the map
---@return integer index Within 1..count, or 1 when the item has no trips
function trip_view.next_index(view, count, on_start, default)
  if count < 1 then return 1 end

  local index = view and view.index
  if not index or index < 1 or index > count then
    -- Nothing of this item's is on the map, or the list has shrunk under it, so start afresh
    if not default or default < 1 or default > count then return 1 end
    return default
  end

  if (view.on_start or false) ~= (on_start or false) then
    -- The other end of the trip being shown: something new without moving on
    return index
  end

  -- This click would redraw what is already there, so move on instead
  index = index + 1
  return index > count and 1 or index
end

--- The trip that is actually on the map right now.
---
--- Three things have to hold, and every caller needs all three: the drawing is still up, the item
--- is still in the history the row is drawn from, and the remembered index still points at one of
--- its trips. The Longest trip row offers to stop listing "the trip on the map", so the tooltip
--- and the click that acts on it have to agree on which trip that is, or the row promises
--- something the click does not do.
---
--- `is_shown` is passed in rather than required, to keep this module free of Factorio globals
---@param player_table PlayerData|nil
---@param networkdata LINetworkData|nil The network the row is drawn from, which need not be the
---  one the trip was shown in: the player may have moved to another network since
---@param is_shown fun(object_id: uint64|nil): boolean Whether a drawing is still on the map
---@return string|nil key The item whose trip is shown, or nil if none of them is
---@return integer|nil index Which of that item's longest trips
---@return TripRecord|nil trip The trip itself
function trip_view.shown(player_table, networkdata, is_shown)
  local view = player_table and player_table.trip_view
  if not view or not networkdata then return nil end
  -- A trip shown in another network is not this row's to offer: the drawing may well still be up,
  -- but the player never looked at anything of this network's. Views saved before the network was
  -- recorded are treated the same way, and come back on the next click
  if view.network_id ~= networkdata.id then return nil end
  if not is_shown(view.object_id) then return nil end
  local history = networkdata.delivery_history
  local entry = history and history[view.key]
  -- The list can shrink under the index: another player ignoring a trip removes it from the
  -- shared history while this player's view still points past the end
  local trip = entry and entry.top_trips and entry.top_trips[view.index]
  if not trip then return nil end
  return view.key, view.index, trip
end

return trip_view
