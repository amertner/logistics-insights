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

return trip_view
