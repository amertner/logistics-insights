-- This code is originally from FactorySearch v1.13.3
local math2d = require("math2d")
local game_state = require("scripts.game-state")

local add_vector = math2d.position.add
local subtract_vector = math2d.position.subtract
local rotate_vector = math2d.position.rotate_vector

local LINE_COLOR = { r = 0, g = 0.9, b = 0, a = 1 }
local LINE_WIDTH = 4
local HALF_WIDTH = (LINE_WIDTH / 2) / 32  -- 32 pixels per tile
local ARROW_TARGET_OFFSET = { 0, -1 }
local ARROW_ORIENTATED_OFFSET = { 0, -1 }

local ResultLocation = {}

---@param player LuaPlayer
function ResultLocation.clear_markers(player)
  -- Clear all old markers belonging to player
  if #game.players == 1 then
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
function ResultLocation.draw_markers(player, surface, items)
  local time_to_live = player.mod_settings["li-highlight-duration"].value * 60
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
          color = LINE_COLOR,
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
        color = LINE_COLOR,
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
        target = item.robot_order_queue[1].target or nil
        if target then
            targetpos = target.position or nil
        end
    else
        targetpos = nil
    end

    rendering.draw_sprite{
      sprite = "li_arrow",
      x_scale = 1,
      y_scale = 1,
      target = {entity=item, offset=ARROW_TARGET_OFFSET},
      --use_target_orientation = true,
      orientation_target = targetpos,
      oriented_offset = ARROW_ORIENTATED_OFFSET,
      surface = surface,
      time_to_live = player.mod_settings["fs-highlight-duration"].value * 60,
      players = {player},
    }
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

---@param player LuaPlayer
---@param results ResultLocationData
function ResultLocation.open(player, results, change_position)
  local surface_name = results.surface
  local position = results.position
  local zoom_level = player.mod_settings["li-initial-zoom"].value * player.display_resolution.width / 1920

  if change_position then
    player.set_controller{
      type = defines.controllers.remote,
      position = position,
      surface = surface_name,
    }
    player.zoom = zoom_level -- TODO zoom out when showing map tags
  end

  data = {
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