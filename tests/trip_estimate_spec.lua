local mock = require("tests.mocks.factorio")

describe("trip-estimate", function()
  local trip_estimate

  --- A network whose logistic range is decided by `covers`, recording every position it is asked about
  ---@param covers fun(pos: table): boolean
  local function network_mock(covers)
    local asked = {}
    return {
      valid = true,
      asked = asked,
      find_cell_closest_to = function(pos)
        asked[#asked + 1] = { x = pos.x, y = pos.y }
        return { is_in_logistic_range = function(p) return covers(p) end }
      end,
    }
  end

  --- Stand in for prototypes.get_entity_filtered, which the shared mock doesn't provide
  local function set_robot_prototypes(list)
    prototypes.get_entity_filtered = function() return list end
  end

  --- A real Chunker holding `count` entities, so chunk counting matches the mod's own
  ---@param count number
  ---@param size? number Chunk size, when it should differ from the setting
  local function chunker_with(count, size)
    local c = require("scripts.chunker").new()
    c.processing_count = count
    if size then c.CHUNK_SIZE = size end
    return c
  end

  before_each(function()
    mock.fresh()
    storage.global = { chunk_size = 400, gather_quality_data = true }
    trip_estimate = require("scripts.trip-estimate")
  end)

  describe("pass_ticks()", function()
    it("counts the chunks a pass takes", function()
      local nwd = { bot_chunker = chunker_with(1000, 400) }
      assert.are.equal(15, trip_estimate.pass_ticks(nwd, 5)) -- 3 chunks
    end)

    it("does not round an exact multiple up", function()
      local nwd = { bot_chunker = chunker_with(800, 400) }
      assert.are.equal(10, trip_estimate.pass_ticks(nwd, 5)) -- 2 chunks
    end)

    it("falls back to the network's bot count when nothing is being processed", function()
      local nwd = {
        bot_chunker = chunker_with(0, 400),
        bot_items = { ["logistic-robot-total"] = 1200 },
      }
      assert.are.equal(15, trip_estimate.pass_ticks(nwd, 5)) -- 3 chunks
    end)

    it("is at least one interval with no bots", function()
      local nwd = { bot_chunker = chunker_with(0, 400) }
      assert.are.equal(5, trip_estimate.pass_ticks(nwd, 5))
    end)

    it("survives a missing chunker", function()
      assert.are.equal(5, trip_estimate.pass_ticks({}, 5))
      assert.are.equal(5, trip_estimate.pass_ticks(nil, 5))
    end)
  end)

  describe("bot_speed()", function()
    before_each(function()
      game.forces = { player = { worker_robots_speed_modifier = 0 } }
    end)

    it("uses the prototype speed with no research", function()
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 } })
      assert.are.equal(0.05, trip_estimate.bot_speed("player"))
    end)

    it("scales with the force's research below the cap", function()
      game.forces.player.worker_robots_speed_modifier = 1
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 } })
      assert.are.equal(0.1, trip_estimate.bot_speed("player"))
    end)

    it("is capped by max_speed", function()
      game.forces.player.worker_robots_speed_modifier = 9
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 } })
      assert.are.equal(0.2, trip_estimate.bot_speed("player"))
    end)

    it("leaves research uncapped when the prototype sets no max_speed", function()
      -- The vanilla logistic robot has speed but no max_speed, so a researched bot is much faster
      game.forces.player.worker_robots_speed_modifier = 7
      set_robot_prototypes({ { speed = 0.05 } })
      assert.are.equal(0.4, trip_estimate.bot_speed("player"))
    end)

    it("takes the fastest of several prototypes", function()
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 }, { speed = 0.09, max_speed = 0.3 } })
      assert.are.equal(0.09, trip_estimate.bot_speed("player"))
    end)

    it("treats an unknown force as having no research", function()
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 } })
      assert.are.equal(0.05, trip_estimate.bot_speed("nosuchforce"))
      assert.are.equal(0.05, trip_estimate.bot_speed(nil))
    end)

    it("is zero when there are no logistic robot prototypes", function()
      set_robot_prototypes({})
      assert.are.equal(0, trip_estimate.bot_speed("player"))
    end)
  end)

  describe("pickup_extension() for a bot that was already being watched", function()
    local from = { x = 0, y = 0 }
    local to = { x = 10, y = 0 }

    it("is zero without an estimate", function()
      assert.are.equal(0, trip_estimate.pickup_extension(nil, from, to, true))
    end)

    it("is zero, not a NaN, when both ends are in the same place", function()
      local est = { network = nil, max_tiles = 10 }
      assert.are.equal(0, trip_estimate.pickup_extension(est, from, { x = 0, y = 0 }, true))
    end)

    it("uses the whole flight-time bound when there is no network to trim against", function()
      assert.are.equal(10, trip_estimate.pickup_extension({ network = nil, max_tiles = 10 }, from, to, true))
      assert.are.equal(10,
        trip_estimate.pickup_extension({ network = { valid = false }, max_tiles = 10 }, from, to, true))
    end)

    it("keeps the whole bound when the network covers all of it", function()
      local net = network_mock(function() return true end)
      assert.are.equal(10, trip_estimate.pickup_extension({ network = net, max_tiles = 10 }, from, to, true))
    end)

    it("trims to the last covered step", function()
      -- Coverage stops 5 tiles back, so only the steps at 2 and 4 are inside it
      local net = network_mock(function(p) return p.x > -5 end)
      assert.are.equal(4, trip_estimate.pickup_extension({ network = net, max_tiles = 10 }, from, to, true))
    end)

    it("is zero when nothing behind the bot is covered", function()
      local net = network_mock(function() return false end)
      assert.are.equal(0, trip_estimate.pickup_extension({ network = net, max_tiles = 10 }, from, to, true))
    end)

    it("looks away from the delivery end, never towards it", function()
      local net = network_mock(function() return true end)
      trip_estimate.pickup_extension({ network = net, max_tiles = 10 }, from, to, true)
      assert.is_true(#net.asked > 0)
      for _, pos in ipairs(net.asked) do
        assert.is_true(pos.x < 0) -- The destination is at +x, so the pickup is back at -x
        assert.are.equal(0, pos.y)
      end
    end)

    it("stays on the line through both ends when the trip is diagonal", function()
      local net = network_mock(function() return true end)
      trip_estimate.pickup_extension({ network = net, max_tiles = 10 }, { x = 0, y = 0 }, { x = 10, y = 10 }, true)
      for _, pos in ipairs(net.asked) do
        assert.is_true(pos.x < 0 and pos.y < 0)
        assert.is_true(math.abs(pos.x - pos.y) < 1e-9) -- 45 degrees, so x and y move together
      end
    end)

    it("draws nothing when a pass is too quick for a bot to have moved a whole tile", function()
      -- 3 chunks of 5 ticks at 0.05 tiles/tick is only 0.75 tiles, below the floor
      local net = network_mock(function() return true end)
      assert.are.equal(0, trip_estimate.pickup_extension({ network = net, max_tiles = 0.75 }, from, to, true))
    end)

    it("checks the exact end when the bound is shorter than one step", function()
      local net = network_mock(function() return true end)
      assert.are.equal(1, trip_estimate.pickup_extension({ network = net, max_tiles = 1 }, from, to, true))
      assert.are.equal(1, #net.asked)
    end)
  end)

  describe("logistic_boxes()", function()
    local function cell(x, y, radius, owner_valid)
      return {
        logistic_radius = radius,
        owner = { valid = owner_valid ~= false, position = { x = x, y = y } },
      }
    end

    it("turns each cell into the square it supplies", function()
      local boxes = trip_estimate.logistic_boxes({ valid = true, cells = { cell(10, 20, 25) } })
      assert.are.same({ { left = -15, top = -5, right = 35, bottom = 45 } }, boxes)
    end)

    it("has nothing to go on without a usable network", function()
      assert.is_nil(trip_estimate.logistic_boxes(nil))
      assert.is_nil(trip_estimate.logistic_boxes({ valid = false, cells = {} }))
      assert.is_nil(trip_estimate.logistic_boxes({ valid = true }))
    end)

    it("skips cells that supply nothing", function()
      local boxes = trip_estimate.logistic_boxes({ valid = true, cells = {
        cell(0, 0, 0), cell(0, 0, nil), cell(0, 0, 25, false),
      } })
      assert.are.equal(0, #boxes)
    end)
  end)

  describe("coverage_distance()", function()
    local origin = { x = 0, y = 0 }
    local function box(cx, cy, r)
      return { left = cx - r, top = cy - r, right = cx + r, bottom = cy + r }
    end
    -- Straight back along -x, the direction a bot heading to (50, 0) came from
    local back = { -1, 0 }

    it("reaches the far edge of a square behind the bot", function()
      assert.are.equal(50, trip_estimate.coverage_distance({ box(-40, 0, 10) }, origin, back[1], back[2]))
    end)

    it("reaches the far edge of a square the bot is standing in", function()
      assert.are.equal(10, trip_estimate.coverage_distance({ box(0, 0, 10) }, origin, back[1], back[2]))
    end)

    it("ignores squares ahead of the bot, towards the delivery", function()
      assert.are.equal(0, trip_estimate.coverage_distance({ box(40, 0, 10) }, origin, back[1], back[2]))
    end)

    it("ignores squares the line never crosses", function()
      assert.are.equal(0, trip_estimate.coverage_distance({ box(-40, 100, 10) }, origin, back[1], back[2]))
    end)

    it("takes the furthest square, across a gap in coverage", function()
      -- Bots fly over ground no roboport supplies, so a gap must not cut the range short
      local boxes = { box(-20, 0, 10), box(-500, 0, 10) }
      assert.are.equal(510, trip_estimate.coverage_distance(boxes, origin, back[1], back[2]))
    end)

    it("handles a ray straight along the y axis", function()
      -- Dividing by a zero component would otherwise give a NaN
      assert.are.equal(50, trip_estimate.coverage_distance({ box(0, -40, 10) }, origin, 0, -1))
      assert.are.equal(0, trip_estimate.coverage_distance({ box(100, -40, 10) }, origin, 0, -1))
    end)

    it("handles a diagonal ray", function()
      local d = trip_estimate.coverage_distance({ box(-15, -15, 5) }, origin, -0.5 ^ 0.5, -0.5 ^ 0.5)
      assert.is_true(math.abs(d - 20 * math.sqrt(2)) < 0.001)
    end)

    it("is zero with no squares", function()
      assert.are.equal(0, trip_estimate.coverage_distance(nil, origin, back[1], back[2]))
      assert.are.equal(0, trip_estimate.coverage_distance({}, origin, back[1], back[2]))
    end)
  end)

  describe("pickup_extension() for a bot that was never watched before", function()
    local from = { x = 0, y = 0 }
    local to = { x = 50, y = 0 }

    it("reaches back to the edge of the network, not just one scan pass", function()
      local est = {
        max_tiles = 2,
        network = { valid = true, cells = {
          { logistic_radius = 25, owner = { valid = true, position = { x = -100, y = 0 } } },
        } },
      }
      assert.are.equal(125, trip_estimate.pickup_extension(est, from, to, false))
    end)

    it("collects the network's squares only once, however many trips are drawn", function()
      local reads = 0
      local est = {
        max_tiles = 2,
        network = { valid = true },
      }
      setmetatable(est.network, { __index = function(_, k)
        if k == "cells" then
          reads = reads + 1
          return { { logistic_radius = 25, owner = { valid = true, position = { x = -100, y = 0 } } } }
        end
      end })
      trip_estimate.pickup_extension(est, from, to, false)
      trip_estimate.pickup_extension(est, from, to, false)
      trip_estimate.pickup_extension(est, from, to, false)
      assert.are.equal(1, reads) -- network.cells is expensive, so it is read once and shared
    end)

    it("draws nothing when the network does not reach behind the bot", function()
      local est = {
        max_tiles = 2,
        network = { valid = true, cells = {
          { logistic_radius = 25, owner = { valid = true, position = { x = 500, y = 0 } } },
        } },
      }
      assert.are.equal(0, trip_estimate.pickup_extension(est, from, to, false))
    end)

    it("draws nothing when there is no network left to ask", function()
      assert.are.equal(0, trip_estimate.pickup_extension({ max_tiles = 2, network = nil }, from, to, false))
    end)

    it("never asks the network about single positions, as a tracked trip does", function()
      local asked = 0
      local est = {
        max_tiles = 2,
        network = {
          valid = true,
          cells = { { logistic_radius = 25, owner = { valid = true, position = { x = -100, y = 0 } } } },
          find_cell_closest_to = function() asked = asked + 1 return nil end,
        },
      }
      trip_estimate.pickup_extension(est, from, to, false)
      assert.are.equal(0, asked)
    end)
  end)

  describe("for_network()", function()
    before_each(function()
      game.forces = { player = { worker_robots_speed_modifier = 0, logistic_networks = {} } }
      set_robot_prototypes({ { speed = 0.05, max_speed = 0.2 } })
      local scheduler = require("scripts.scheduler")
      scheduler.register({ name = "player-network-bot-chunk", interval = 5, fn = function() end })
    end)

    it("is nil without network data", function()
      assert.is_nil(trip_estimate.for_network(nil))
    end)

    it("bounds the estimate by speed over a full pass", function()
      local est = trip_estimate.for_network({
        id = 1, surface = "nauvis", force_name = "player",
        bot_chunker = chunker_with(12000, 400),
      })
      assert.is_not_nil(est)
      assert.are.equal(0.05 * 150, est.max_tiles) -- 30 chunks of 5 ticks
    end)

    it("still gives an estimate when a pass is too quick to matter", function()
      -- A trip whose bot was never tracked is bounded by the network, not by the pass length
      local est = trip_estimate.for_network({
        id = 1, surface = "nauvis", force_name = "player",
        bot_chunker = chunker_with(400, 400),
      })
      assert.is_not_nil(est)
      assert.are.equal(0.05 * 5, est.max_tiles)
    end)
  end)
end)
