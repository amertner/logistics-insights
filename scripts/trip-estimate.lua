--- Estimating how much of a trip happened before the mod first saw the bot.
---
--- When a bot's pickup is never observed, a trip's recorded start is only where the bot happened
--- to be when it was first looked at, so the trip is short by however far it had already flown.
--- Logistic bots fly straight from pickup to drop-off, so the direction of that missing piece is
--- known exactly: the pickup lies on the ray from the delivery end through the recorded start,
--- beyond it. Only the length is unknown, and this module bounds it.
---
--- How far back it could reach depends on whether the bot was already being watched:
---  * Tracked: it was looked at in the previous pass and was not delivering then, so it can only
---    have flown one scan pass unseen. That is a short, tight bound.
---  * Not tracked: the mod had never looked at this bot, typically because scanning of the network
---    had only just started, so it could have been flying for any length of time. All that bounds
---    it then is the network itself, since the pickup chest has to be inside a roboport's
---    logistic area.
---
--- One approximation is baked in, and it is the same one the rest of the trip feature already
--- makes: bots divert to roboports to recharge on long trips, so the observed heading can belong
--- to a leg after a recharge rather than to the chest-to-destination line.
local network_data = require("scripts.network-data")
local scheduler = require("scripts.scheduler")

local math_abs = math.abs
local math_ceil = math.ceil
local math_huge = math.huge
local math_max = math.max
local math_sqrt = math.sqrt

local trip_estimate = {}

trip_estimate.MIN_ESTIMATE_TILES = 1 -- Shorter than this isn't worth a dashed line
trip_estimate.CLIP_STEP_TILES = 2 -- How finely a tracked trip's estimate is trimmed to the network

local EPSILON = 1e-9 -- Below this a ray counts as parallel to an axis
local BOT_CHUNK_TASK = "player-network-bot-chunk" -- The scheduler task that looks at bots

--- The axis-aligned square one roboport supplies, in tiles
---@class LogisticBox
---@field left number
---@field top number
---@field right number
---@field bottom number

--- A bound on where an estimated trip could really have started, shared by every trip drawn at once
---@class TripEstimate
---@field network LuaLogisticNetwork|nil -- To bound the estimate by the network's coverage
---@field max_tiles number -- How far a bot could fly in one scan pass, the bound for a tracked trip
---@field boxes LogisticBox[]|nil -- The network's logistic squares, collected on first need
---@field boxes_done boolean|nil -- True once collecting them has been tried

--- How long one full pass over a network's bots takes, which is the longest a bot can go
--- unlooked-at, and so the longest a tracked bot can have been flying unseen
---@param networkdata LINetworkData|nil
---@param interval_ticks number Ticks between bot chunks
---@return number ticks Always at least one interval
function trip_estimate.pass_ticks(networkdata, interval_ticks)
  local chunker = networkdata and networkdata.bot_chunker
  local chunks = (chunker and chunker.num_chunks and chunker:num_chunks()) or 0
  if chunks <= 0 then
    -- Nothing is being processed right now, so fall back to the network's own bot count
    local bot_items = networkdata and networkdata.bot_items
    local count = (bot_items and bot_items["logistic-robot-total"]) or 0
    local size = math_max(1, (chunker and chunker.CHUNK_SIZE) or 1)
    chunks = math_ceil(count / size)
  end
  return interval_ticks * math_max(1, chunks)
end

--- The fastest a logistic bot on a force can fly, in tiles per tick. Quality doesn't come into it:
--- no speed scaling for it is exposed, and max_speed caps bonuses where a prototype sets one
---@param force_name string|nil
---@return number tiles_per_tick 0 if there are no logistic robot prototypes
function trip_estimate.bot_speed(force_name)
  local force = force_name and game.forces[force_name]
  local modifier = 1 + ((force and force.worker_robots_speed_modifier) or 0)
  local best = 0
  for _, proto in pairs(prototypes.get_entity_filtered{{filter = "type", type = "logistic-robot"}}) do
    local speed = (proto.speed or 0) * modifier
    local cap = proto.max_speed -- Already includes research bonuses; the vanilla bot sets none
    if cap and cap > 0 and speed > cap then
      speed = cap
    end
    if speed > best then
      best = speed
    end
  end
  return best
end

--- The squares a network supplies, as plain boxes. One pass over the expensive network.cells,
--- reused by every trip drawn at once
---@param network LuaLogisticNetwork|nil
---@return LogisticBox[]|nil boxes nil if there is no usable network
function trip_estimate.logistic_boxes(network)
  if not (network and network.valid) then return nil end
  local cells = network.cells
  if not cells then return nil end
  local boxes = {}
  for _, cell in pairs(cells) do
    local radius = cell.logistic_radius
    local owner = radius and radius > 0 and cell.owner
    -- An unpowered roboport still counts: the pickup already happened, maybe while it had power
    if owner and owner.valid then
      local pos = owner.position
      boxes[#boxes + 1] = {
        left = pos.x - radius, top = pos.y - radius,
        right = pos.x + radius, bottom = pos.y + radius,
      }
    end
  end
  return boxes
end

--- How far along a ray it leaves an axis-aligned box, by the usual slab test
---@param px number Ray origin
---@param py number
---@param ux number Unit direction
---@param uy number
---@param box LogisticBox
---@return number|nil exit Distance along the ray, or nil if it never crosses the box ahead
local function ray_box_exit(px, py, ux, uy, box)
  local near, far = -math_huge, math_huge
  if math_abs(ux) < EPSILON then
    -- Parallel to the y axis, so it is either inside this slab the whole way or misses it
    if px < box.left or px > box.right then return nil end
  else
    local t1, t2 = (box.left - px) / ux, (box.right - px) / ux
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > near then near = t1 end
    if t2 < far then far = t2 end
  end
  if math_abs(uy) < EPSILON then
    if py < box.top or py > box.bottom then return nil end
  else
    local t1, t2 = (box.top - py) / uy, (box.bottom - py) / uy
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > near then near = t1 end
    if t2 < far then far = t2 end
  end
  if far < near or far < 0 then return nil end
  return far
end

--- The furthest point along a ray that is still somewhere a pickup chest could stand. Gaps in
--- coverage don't cut it short, because a bot can fly over ground no roboport supplies
---@param boxes LogisticBox[]|nil
---@param from MapPosition Ray origin
---@param ux number Unit direction
---@param uy number
---@return number tiles
function trip_estimate.coverage_distance(boxes, from, ux, uy)
  if not boxes then return 0 end
  local best = 0
  local px, py = from.x, from.y
  for i = 1, #boxes do
    local exit = ray_box_exit(px, py, ux, uy, boxes[i])
    if exit and exit > best then best = exit end
  end
  return best
end

--- Work out the bound once, to share between the trips drawn in one go
---@param networkdata LINetworkData|nil
---@return TripEstimate|nil estimate nil when there is nothing to go on
function trip_estimate.for_network(networkdata)
  if not networkdata then return nil end
  local interval = scheduler.get_interval(BOT_CHUNK_TASK)
  if not interval then return nil end

  return {
    network = network_data.get_LuaNetwork(networkdata),
    max_tiles = trip_estimate.bot_speed(networkdata.force_name)
      * trip_estimate.pass_ticks(networkdata, interval),
  }
end

--- Trim a tracked trip's estimate to the network, stepping out from the start. Cheap because the
--- distance is short: the bot only had one scan pass to cover it
---@param estimate TripEstimate
---@param from MapPosition
---@param ux number
---@param uy number
---@return number tiles
local function stepped_coverage(estimate, from, ux, uy)
  local network = estimate.network
  local max_tiles = estimate.max_tiles
  if not (network and network.valid) then
    -- No network to trim against; the flight-time bound stands on its own
    return max_tiles
  end

  local function in_network(dist)
    local pos = { x = from.x + ux * dist, y = from.y + uy * dist }
    local cell = network.find_cell_closest_to(pos)
    return cell ~= nil and cell.is_in_logistic_range(pos)
  end

  local step = trip_estimate.CLIP_STEP_TILES
  local best = 0
  local dist = step
  while dist < max_tiles do
    if not in_network(dist) then return best end
    best = dist
    dist = dist + step
  end
  -- Every whole step was covered, so the end itself is all that's left to check
  if in_network(max_tiles) then return max_tiles end
  return best
end

--- How much further back along the line from `to` through `from` the pickup could have been
---@param estimate TripEstimate|nil
---@param from MapPosition Where the bot was first seen
---@param to MapPosition Where it was delivering, which fixes the direction
---@param tracked boolean|nil True if the bot was already being watched when the trip started
---@return number tiles 0 when there is nothing worth drawing
function trip_estimate.pickup_extension(estimate, from, to, tracked)
  if not estimate then return 0 end

  -- Away from the delivery end: the bot flew straight, so it came from somewhere along this ray
  local dx, dy = from.x - to.x, from.y - to.y
  local len = math_sqrt(dx * dx + dy * dy)
  if len < EPSILON then return 0 end -- Both ends in the same place, so there is no direction
  local ux, uy = dx / len, dy / len

  local tiles
  if tracked then
    tiles = stepped_coverage(estimate, from, ux, uy)
  else
    -- Never looked at before, so only the network's own reach says where it can have come from
    if not estimate.boxes_done then
      estimate.boxes = trip_estimate.logistic_boxes(estimate.network)
      estimate.boxes_done = true
    end
    tiles = trip_estimate.coverage_distance(estimate.boxes, from, ux, uy)
  end

  if tiles < trip_estimate.MIN_ESTIMATE_TILES then return 0 end
  return tiles
end

return trip_estimate
