-- This code is originally from FactorySearch v1.13.3
-- In Logistics Insights, it's a reduced function used to highlight bots and entities on the map
local math2d = require("math2d")
local utils = require("scripts.utils")

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
---@param surface SurfaceName
---@param items LuaEntity[]
function ResultLocation.draw_arrows(player, surface, items)
  -- For bots, show an arrow pointing towards its destination
  for _, item in pairs(items) do
    if item.name ~= "logistic-robot" then
      return
    end

    if item.robot_order_queue and #item.robot_order_queue > 0 then
        local target = item.robot_order_queue[1].target or nil
        if target then
            local targetpos = target.position or nil
            rendering.draw_sprite{
              sprite = "li_arrow",
              x_scale = 1,
              y_scale = 1,
              target = {entity=item, offset=ARROW_TARGET_OFFSET},
              orientation_target = targetpos,
              oriented_offset = ARROW_ORIENTATED_OFFSET,
              surface = surface,
              time_to_live = player.mod_settings["fs-highlight-duration"].value * 60,
              players = {player},
            }
        end
    else
        -- No target queue or empty: still draw a sprite without orientation_target
        rendering.draw_sprite{
          sprite = "li_arrow",
          x_scale = 1,
          y_scale = 1,
          target = {entity=item, offset=ARROW_TARGET_OFFSET},
          oriented_offset = ARROW_ORIENTATED_OFFSET,
          surface = surface,
          time_to_live = player.mod_settings["fs-highlight-duration"].value * 60,
          players = {player},
        }
    end
  end
end

---@param player LuaPlayer
---@param data ResultLocationData
function ResultLocation.highlight(player, data, draw)
  local surface_name = data.surface

  ResultLocation.clear_markers(player)

  -- In case surface was deleted
  if not game.surfaces[surface_name] then return end

  if draw.arrows then
    ResultLocation.draw_arrows(player, surface_name, data.items)
  end
  if draw.markers then
    ResultLocation.draw_markers(player, surface_name, data.items)
  end
end

local TRIP_TEXT_COLOR = { r = 1, g = 1, b = 1, a = 1 }
local OTHER_TRIP_COLOR = { r = 0, g = 0.45, b = 0, a = 1 } -- Trips other than the one being looked at
local TRIP_LABEL_SCALE = 2 -- Large enough for the item icon in the label to stand out from the ground
local TRIP_LABEL_GAP_TILES = 0.3 -- Between an end's outline and its label
local ARROW_SIZE_TILES = 0.6 -- Size of direction arrows close in
local ARROW_SPACING_TILES = 64 -- Close in, one arrow per chunk
local ARROW_MAX_COUNT = 60 -- Spread arrows further apart on very long trips
local MAP_ARROW_COUNT = 5 -- Arrows along the line in map view
local TRIP_DURATION_FACTOR = 3 -- Trips take longer to follow than other highlights take to look at

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

  -- Close in: an arrow per chunk, or one in the middle of a shorter trip
  local count = math.max(1, math.floor(length / math.max(ARROW_SPACING_TILES, length / ARROW_MAX_COUNT)))
  for i = 1, count do
    draw_arrowhead(player, surface_name, along((i - 0.5) * length / count), dir, ARROW_SIZE_TILES, color, time_to_live, "game")
  end

  -- Map view: a few arrows sized to the trip, visible when zoomed out to see all of it
  local map_size = math.max(ARROW_SIZE_TILES, length / 60)
  for i = 1, MAP_ARROW_COUNT do
    draw_arrowhead(player, surface_name, along(i * length / (MAP_ARROW_COUNT + 1)), dir, map_size, color, time_to_live, "chart")
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
---@return uint64|nil focus_id Id of the highlighted trip's line, to tell whether it is still shown
function ResultLocation.show_trips(player, surface_name, trips, focus, item, focus_on_start)
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

    local from_marker = trip_endpoint_marker(surface, from, trip.exact)
    local to_marker = trip_endpoint_marker(surface, to, true)
    ResultLocation.draw_markers(player, surface_name, { from_marker, to_marker }, color, time_to_live)
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
    player.zoom = zoom_level -- #TODO zoom out when showing map tags
  end

  local data = {
    surface = surface_name,
    position = position,
    items = results.items or {}
  }

  ResultLocation.highlight(player, data, {
    arrows = false, -- Still work in progress
    markers = true
  })
end


return ResultLocation