-- This code is originally from FactorySearch v1.13.3
-- In Logistics Insights, it's a reduced function used to highlight bots and entities on the map
local math2d = require("math2d")
local utils = require("scripts.utils")
local trip_estimate = require("scripts.trip-estimate")

local add_vector = math2d.position.add
local subtract_vector = math2d.position.subtract
local rotate_vector = math2d.position.rotate_vector

local LINE_COLOR = { r = 0, g = 0.9, b = 0, a = 1 }
local LINE_WIDTH = 4
local HALF_WIDTH = (LINE_WIDTH / 2) / 32  -- 32 pixels per tile
local ARROW_TARGET_OFFSET = { 0, -1 }
local ARROW_ORIENTATED_OFFSET = { 0, -1 }

local ResultLocation = {}

---@param player LuaPlayer|nil
function ResultLocation.clear_markers(player)
  -- Clear all old markers belonging to player
  if #game.players == 1 or not player then
    rendering.clear("logistics-insights")
  else
    local objects = rendering.get_all_objects("logistics-insights")
    for _, object in pairs(objects) do
      if object.players[1].index == player.index then
        object.destroy()
      end
    end
  end
end

---@param player LuaPlayer
---@param surface SurfaceName
---@param items LuaEntity[]
---@param color? Color Defaults to the usual highlight green
---@param time_to_live? number Ticks; defaults to the player's highlight duration
function ResultLocation.draw_markers(player, surface, items, color, time_to_live)
  color = color or LINE_COLOR
  time_to_live = time_to_live or player.mod_settings["li-highlight-duration"].value * 60
  -- Draw new markers
  for _, item in pairs(items) do
    local selection_box
    if item.selection_box then
      selection_box = item.selection_box
    elseif item.bounding_box then
      selection_box = item.bounding_box
    else
      -- No selection box, skip this item
      selection_box = {}
    end
    if selection_box.orientation then
      local angle = selection_box.orientation * 360

      -- Four corners
      local left_top = selection_box.left_top
      local right_bottom = selection_box.right_bottom
      local right_top = {x = right_bottom.x, y = left_top.y}
      local left_bottom = {x = left_top.x, y = right_bottom.y}

      -- Extend the end of each line by HALF_WIDTH so that corners are still right angles despite `width`
      local lines = {
        {from = {x = left_top.x - HALF_WIDTH, y = left_top.y}, to = {x = right_top.x + HALF_WIDTH, y = right_top.y}},  -- Top
        {from = {x = left_bottom.x - HALF_WIDTH, y = left_bottom.y}, to = {x = right_bottom.x + HALF_WIDTH, y = right_bottom.y}},  -- Bottom
        {from = {x = left_top.x, y = left_top.y - HALF_WIDTH}, to = {x = left_bottom.x, y = left_bottom.y + HALF_WIDTH}},  -- Left
        {from = {x = right_top.x, y = right_top.y - HALF_WIDTH}, to = {x = right_bottom.x, y = right_bottom.y + HALF_WIDTH}},  -- Right
      }

      local center = {x = (left_top.x + right_bottom.x) / 2, y = (left_top.y + right_bottom.y) / 2}
      for _, line in pairs(lines) do
        -- Translate each point to origin, rotate, then translate back
        local rotated_from = add_vector(rotate_vector(subtract_vector(line.from, center), angle), center)
        local rotated_to = add_vector(rotate_vector(subtract_vector(line.to, center), angle), center)

        rendering.draw_line{
          color = color,
          width = LINE_WIDTH,
          from = rotated_from,
          to = rotated_to,
          surface = surface,
          time_to_live = time_to_live,
          players = {player},
        }
      end
    else
      rendering.draw_rectangle{
        color = color,
        width = LINE_WIDTH,
        filled = false,
        left_top = selection_box.left_top,
        right_bottom = selection_box.right_bottom,
        surface = surface,
        time_to_live = time_to_live,
        players = {player},
      }
    end
  end
end

---@param player LuaPlayer
---@param data ResultLocationData
function ResultLocation.highlight(player, data)
  local surface_name = data.surface

  ResultLocation.clear_markers(player)

  -- In case surface was deleted
  if not game.surfaces[surface_name] then return end

  ResultLocation.draw_markers(player, surface_name, data.items)
end

local TRIP_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }
local OTHER_TRIP_COLOR = { r = 0, g = 0.45, b = 0, a = 1 } -- Trips other than the one being looked at
local TRIP_LABEL_SCALE = 2 -- Large enough for the item icon in the label to stand out from the ground
local TRIP_LABEL_GAP_TILES = 0.3 -- Between an end's outline and its label
local ARROW_SIZE_TILES = 0.6 -- Size of direction arrows close in
local ARROW_SPACING_TILES = 64 -- Close in, at most a chunk between arrows
local ARROW_END_TILES = 4 -- Close in, an arrow this far from each end, just clear of the outline
local ARROW_MAX_COUNT = 60 -- Spread arrows further apart on very long trips
local MAP_ARROW_COUNT = 5 -- Arrows along the line in map view
local TRIP_DURATION_FACTOR = 3 -- Trips take longer to follow than other highlights take to look at
-- Dim the green as well as the alpha: in map view an alpha-only difference washes out
local ESTIMATE_COLOR = { r = 0, g = 0.7, b = 0, a = 0.7 } -- Where the pickup might have been
local OTHER_ESTIMATE_COLOR = { r = 0, g = 0.35, b = 0, a = 0.6 } -- The same, for trips not being looked at
local ESTIMATE_DASH_TILES = 1 -- Dash length close in
local ESTIMATE_GAP_TILES = 0.8 -- Gap between dashes close in
local MAP_ESTIMATE_DASHES = 4 -- Roughly this many dashes in map view, however long the estimate
local ESTIMATE_MARKER_RADIUS = 0.5 -- Matches the tile-sized box an outline would have drawn

--- How long trips stay on the map, in ticks: longer than other highlights. 0 means forever
---@param player LuaPlayer
---@return number
function ResultLocation.trip_time_to_live(player)
  return player.mod_settings["li-highlight-duration"].value * 60 * TRIP_DURATION_FACTOR
end

--- Whether something drawn on the map is still there: it may have expired, or been cleared by
--- another highlight
---@param object_id uint64|nil
---@return boolean
function ResultLocation.is_shown(object_id)
  local object = object_id and rendering.get_object_by_id(object_id)
  return object ~= nil and object.valid
end

--- The zoom level set by the player's highlight zoom setting
---@param player LuaPlayer
local function default_zoom(player)
  return player.mod_settings["li-initial-zoom"].value * player.display_resolution.width / 1920
end

--- The entity at a position to outline, or a tile-sized box if there is none (or it's gone)
---@param surface LuaSurface
---@param pos MapPosition
---@param look_for_entity boolean False if the position is not expected to be an entity
local function trip_endpoint_marker(surface, pos, look_for_entity)
  if look_for_entity then
    for _, entity in pairs(surface.find_entities_filtered{ position = pos }) do
      if entity.type ~= "logistic-robot" and entity.type ~= "construction-robot" then
        return entity
      end
    end
  end
  return { selection_box = {
    left_top = { x = pos.x - 0.5, y = pos.y - 0.5 },
    right_bottom = { x = pos.x + 0.5, y = pos.y + 0.5 },
  } }
end

--- Where to put a trip end's label: beside its outline, vertically centred, on the side away from
--- the trip line so the line doesn't run through the label
---@param marker {selection_box: BoundingBox} The outlined entity, or a tile-sized box
---@param other_end MapPosition The other end of the trip
---@return MapPosition anchor
---@return TextAlign alignment
local function trip_label_anchor(marker, other_end)
  local box = marker.selection_box
  local left, right = box.left_top.x, box.right_bottom.x
  local y = (box.left_top.y + box.right_bottom.y) / 2
  if other_end.x > (left + right) / 2 then
    return { x = left - TRIP_LABEL_GAP_TILES, y = y }, "right"
  end
  return { x = right + TRIP_LABEL_GAP_TILES, y = y }, "left"
end

--- Draw an arrowhead (two short lines) centred on a point, pointing along a unit vector
---@param player LuaPlayer
---@param surface_name string
---@param centre MapPosition
---@param dir {x: number, y: number} Unit vector the arrow points along
---@param size number Arrow size in tiles
---@param color Color
---@param time_to_live number
---@param render_mode ScriptRenderMode
local function draw_arrowhead(player, surface_name, centre, dir, size, color, time_to_live, render_mode)
  local half = size / 2
  local tip = { x = centre.x + dir.x * half, y = centre.y + dir.y * half }
  -- The two arms sweep back from the tip, one on each side of the line
  for _, side in pairs({ 1, -1 }) do
    rendering.draw_line{
      color = color,
      width = LINE_WIDTH,
      from = {
        x = centre.x - dir.x * half - dir.y * half * side,
        y = centre.y - dir.y * half + dir.x * half * side,
      },
      to = tip,
      surface = surface_name,
      time_to_live = time_to_live,
      players = {player},
      render_mode = render_mode,
    }
  end
end

--- Draw evenly spaced arrows along a trip, pointing from its start to its end
---@param player LuaPlayer
---@param surface_name string
---@param from MapPosition
---@param to MapPosition
---@param color Color
---@param time_to_live number
local function draw_trip_arrows(player, surface_name, from, to, color, time_to_live)
  local length = utils.distance(from, to)
  if length < ARROW_SIZE_TILES * 2 then return end
  local dir = { x = (to.x - from.x) / length, y = (to.y - from.y) / length }
  local function along(dist)
    return { x = from.x + dir.x * dist, y = from.y + dir.y * dist }
  end

  -- Close in: an arrow just off each end, so the direction shows as soon as the view lands there,
  -- and more between them at most a chunk apart. A short trip gets one in the middle
  local span = length - 2 * ARROW_END_TILES
  if span < 2 * ARROW_END_TILES then
    draw_arrowhead(player, surface_name, along(length / 2), dir, ARROW_SIZE_TILES, color, time_to_live, "game")
  else
    local gaps = math.min(ARROW_MAX_COUNT, math.ceil(span / ARROW_SPACING_TILES))
    for i = 0, gaps do
      draw_arrowhead(player, surface_name, along(ARROW_END_TILES + i * span / gaps), dir, ARROW_SIZE_TILES, color, time_to_live, "game")
    end
  end

  -- Map view: a few arrows sized to the trip, visible when zoomed out to see all of it
  local map_size = math.max(ARROW_SIZE_TILES, length / 60)
  for i = 1, MAP_ARROW_COUNT do
    draw_arrowhead(player, surface_name, along(i * length / (MAP_ARROW_COUNT + 1)), dir, map_size, color, time_to_live, "chart")
  end
end

--- Extend a trip back from where the bot was first seen, as far as it could have flown since the
--- scan pass that last looked at it. Dashed, because the pickup could be anywhere along it
---@param player LuaPlayer
---@param surface_name string
---@param from MapPosition Where the bot was first seen
---@param to MapPosition The delivery end, which fixes the direction
---@param dist number How far back to draw, in tiles
---@param color Color
---@param time_to_live number
local function draw_trip_estimate(player, surface_name, from, to, dist, color, time_to_live)
  local length = utils.distance(from, to)
  if length <= 0 or dist <= 0 then return end
  -- Away from the delivery end, along the line the bot flew
  local dir = { x = (from.x - to.x) / length, y = (from.y - to.y) / length }
  local far = { x = from.x + dir.x * dist, y = from.y + dir.y * dist }

  for _, render_mode in pairs({ "game", "chart" }) do
    -- Scale the dashes to the estimate in map view, so a short one isn't a solid smudge
    local dash = ESTIMATE_DASH_TILES
    if render_mode == "chart" then
      dash = math.max(dash, dist / (MAP_ESTIMATE_DASHES * 2))
    end
    rendering.draw_line{
      color = color,
      width = LINE_WIDTH,
      from = from,
      to = far,
      dash_length = dash,
      gap_length = dash * ESTIMATE_GAP_TILES / ESTIMATE_DASH_TILES,
      surface = surface_name,
      time_to_live = time_to_live,
      players = {player},
      render_mode = render_mode,
    }
  end
end

--- Draw a label beside one end of a trip, in both game and map view
---@param player LuaPlayer
---@param surface_name string
---@param marker {selection_box: BoundingBox} The end's outline
---@param other_end MapPosition The other end of the trip, so the label can avoid the line
---@param text LocalisedString
---@param time_to_live number
local function draw_trip_label(player, surface_name, marker, other_end, text, time_to_live)
  local anchor, alignment = trip_label_anchor(marker, other_end)
  for _, render_mode in pairs({ "game", "chart" }) do
    rendering.draw_text{
      text = text,
      target = anchor,
      surface = surface_name,
      color = TRIP_TEXT_COLOR,
      scale = TRIP_LABEL_SCALE,
      scale_with_zoom = true,
      alignment = alignment,
      vertical_alignment = "middle",
      use_rich_text = true,
      time_to_live = time_to_live,
      players = {player},
      render_mode = render_mode,
    }
  end
end

--- Show an item's longest trips on the map, and move the player's view to one end of one of them.
--- Each trip's ends are outlined and joined by an arrowed line. The trip being looked at is
--- highlighted and labelled with the item; the others are dimmer and just numbered.
---@param player LuaPlayer
---@param surface_name string
---@param trips TripRecord[] Longest first
---@param focus integer Which trip to highlight and move the view to
---@param item ItemQuality The item that was carried, shown in the labels
---@param focus_on_start boolean True to go to where the trip started, false to go to the delivery end
---@param estimate TripEstimate|nil Bounds how far back a trip with an estimated start could have begun
---@return uint64|nil focus_id Id of the highlighted trip's line, to tell whether it is still shown
function ResultLocation.show_trips(player, surface_name, trips, focus, item, focus_on_start, estimate)
  local surface = game.surfaces[surface_name]
  if not surface or not trips[focus] then return nil end
  ResultLocation.clear_markers(player)
  local time_to_live = ResultLocation.trip_time_to_live(player)
  local focus_id
  local icon = item.quality == "normal" and ("[item=" .. item.name .. "]")
    or ("[item=" .. item.name .. ",quality=" .. item.quality .. "]")
  local numbered = #trips > 1

  -- Draw the highlighted trip last, so it's on top where trips overlap
  local order = {}
  for i = 1, #trips do
    if i ~= focus then order[#order + 1] = i end
  end
  order[#order + 1] = focus

  for _, i in ipairs(order) do
    local trip = trips[i]
    local from = { x = trip.from_x, y = trip.from_y }
    local to = { x = trip.to_x, y = trip.to_y }
    local is_focus = i == focus
    local color = is_focus and LINE_COLOR or OTHER_TRIP_COLOR

    if not trip.exact then
      -- The start is only where the bot was first seen, so show how much further back it could go:
      -- one scan pass of flight if the bot was already being watched, otherwise as far back as the
      -- network reaches. Drawn first, so the solid line stays on top where the two meet
      local back = trip_estimate.pickup_extension(estimate, from, to, trip.tracked)
      if back > 0 then
        draw_trip_estimate(player, surface_name, from, to, back,
          is_focus and ESTIMATE_COLOR or OTHER_ESTIMATE_COLOR, time_to_live)
      end
    end

    local from_marker = trip_endpoint_marker(surface, from, trip.exact)
    local to_marker = trip_endpoint_marker(surface, to, true)
    local markers = { to_marker }
    if trip.exact then
      markers[#markers + 1] = from_marker
    else
      -- Nothing stands where the bot was first seen, so ring the spot rather than outline a box
      -- that would suggest a chest. Close in only, like the outlines it replaces
      rendering.draw_circle{
        color = color,
        width = LINE_WIDTH,
        filled = false,
        target = from,
        radius = ESTIMATE_MARKER_RADIUS,
        surface = surface_name,
        time_to_live = time_to_live,
        players = {player},
      }
    end
    ResultLocation.draw_markers(player, surface_name, markers, color, time_to_live)
    -- Markers only show up close in, so draw the line in map view too
    for _, render_mode in pairs({ "game", "chart" }) do
      local line = rendering.draw_line{
        color = color,
        width = LINE_WIDTH,
        from = from,
        to = to,
        surface = surface_name,
        time_to_live = time_to_live,
        players = {player},
        render_mode = render_mode,
      }
      if is_focus and render_mode == "game" then
        focus_id = line.id
      end
    end
    draw_trip_arrows(player, surface_name, from, to, color, time_to_live)

    local number = numbered and {"item-row.trip-number-1n", i} or nil
    local from_text, to_text
    if is_focus then
      -- Name the item with its icon, so it's clear what the trip was once the window is out of sight
      from_text = { trip.exact and "item-row.trip-from-label" or "item-row.trip-first-seen-label", icon }
      to_text = { "item-row.trip-to-label", icon, utils.format_distances({trip.dist}) }
      if number then
        from_text = { "", number, " ", from_text }
        to_text = { "", number, " ", to_text }
      end
    elseif number then
      from_text, to_text = number, number
    end
    if from_text then
      draw_trip_label(player, surface_name, from_marker, to, from_text, time_to_live)
      draw_trip_label(player, surface_name, to_marker, from, to_text, time_to_live)
    end
  end

  local target = trips[focus]
  player.set_controller{
    type = defines.controllers.remote,
    position = focus_on_start and { x = target.from_x, y = target.from_y } or { x = target.to_x, y = target.to_y },
    surface = surface_name,
  }
  player.zoom = default_zoom(player)
  return focus_id
end

---@param player LuaPlayer
---@param results ResultLocationData
function ResultLocation.open(player, results, change_position)
  local surface_name = results.surface
  local position = results.position
  local zoom_level = default_zoom(player)

  if change_position then
    player.set_controller{
      type = defines.controllers.remote,
      position = position,
      surface = surface_name,
    }
    player.zoom = zoom_level
  end

  local data = {
    surface = surface_name,
    position = position,
    items = results.items or {}
  }

  ResultLocation.highlight(player, data)
end


return ResultLocation