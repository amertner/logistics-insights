local mock = require("tests.mocks.factorio")

describe("trip-view", function()
  local trip_view

  before_each(function()
    mock.fresh()
    trip_view = require("scripts.trip-view")
  end)

  describe("next_index()", function()
    local DEST, START = false, true

    it("starts where the caller asks when nothing is on the map", function()
      assert.are.equal(1, trip_view.next_index(nil, 5, DEST, 1))
      assert.are.equal(3, trip_view.next_index(nil, 5, DEST, 3))
      assert.are.equal(3, trip_view.next_index(nil, 5, START, 3))
    end)

    it("falls back to the longest when the caller asks for a trip that isn't there", function()
      -- The suggestion's trip may have dropped off the list since it was made
      assert.are.equal(1, trip_view.next_index(nil, 3, DEST, 9))
      assert.are.equal(1, trip_view.next_index(nil, 3, DEST, 0))
      assert.are.equal(1, trip_view.next_index(nil, 3, DEST, nil))
    end)

    it("moves on when the click would redraw what is already shown", function()
      assert.are.equal(2, trip_view.next_index({ index = 1, on_start = DEST }, 5, DEST, 1))
      assert.are.equal(4, trip_view.next_index({ index = 3, on_start = START }, 5, START, 1))
    end)

    it("wraps round past the last trip", function()
      assert.are.equal(1, trip_view.next_index({ index = 5, on_start = DEST }, 5, DEST, 1))
    end)

    it("shows the other end of the same trip without moving on", function()
      assert.are.equal(3, trip_view.next_index({ index = 3, on_start = DEST }, 5, START, 1))
      assert.are.equal(3, trip_view.next_index({ index = 3, on_start = START }, 5, DEST, 1))
    end)

    it("treats a view with no end recorded as showing the delivery end", function()
      -- Saved before the end was tracked, so a left-click must still count as a repeat
      assert.are.equal(3, trip_view.next_index({ index = 2 }, 5, DEST, 1))
      assert.are.equal(2, trip_view.next_index({ index = 2 }, 5, START, 1))
    end)

    it("starts afresh when the list has shrunk under the shown trip", function()
      assert.are.equal(1, trip_view.next_index({ index = 5, on_start = DEST }, 2, DEST, 1))
      assert.are.equal(2, trip_view.next_index({ index = 5, on_start = DEST }, 3, DEST, 2))
    end)

    it("stays put when the item has only one trip", function()
      assert.are.equal(1, trip_view.next_index({ index = 1, on_start = DEST }, 1, DEST, 1))
      assert.are.equal(1, trip_view.next_index({ index = 1, on_start = DEST }, 1, START, 1))
    end)

    it("never returns an index for an item with no trips", function()
      assert.are.equal(1, trip_view.next_index(nil, 0, DEST, 1))
      assert.are.equal(1, trip_view.next_index({ index = 1, on_start = DEST }, 0, DEST, 1))
    end)

    it("walks the agreed sequence of clicks", function()
      -- Left, left, right, right, left: no click ever redraws what is already there, and both
      -- ends of a trip stay reachable
      local view = nil
      local function click(on_start)
        local index = trip_view.next_index(view, 5, on_start, 1)
        view = { index = index, on_start = on_start }
        return index
      end
      assert.are.equal(1, click(DEST))
      assert.are.equal(2, click(DEST))
      assert.are.equal(2, click(START))
      assert.are.equal(3, click(START))
      assert.are.equal(3, click(DEST))
    end)
  end)

  describe("shown()", function()
    local DRAWN, GONE = 8001, 8002
    local function is_shown(object_id) return object_id == DRAWN end

    local IRON = "iron-plate|normal"
    local function a_trip(dist) return { dist = dist, to_x = dist, to_y = 0 } end
    local function a_network(id, trips)
      return { id = id, delivery_history = { [IRON] = { top_trips = trips } } }
    end
    --- A player watching trip `index` of IRON, shown while they were in network `network_id`
    local function watching(network_id, index, object_id)
      return { trip_view = { key = IRON, index = index, object_id = object_id or DRAWN,
        network_id = network_id } }
    end

    it("gives back the trip that is on the map", function()
      local nwd = a_network(1, { a_trip(90), a_trip(80), a_trip(70) })
      local key, index, trip = trip_view.shown(watching(1, 2), nwd, is_shown)
      assert.are.equal(IRON, key)
      assert.are.equal(2, index)
      assert.are.equal(80, trip.dist)
    end)

    it("gives back nothing when no trip has been shown", function()
      assert.is_nil(trip_view.shown({}, a_network(1, { a_trip(90) }), is_shown))
      assert.is_nil(trip_view.shown(nil, a_network(1, { a_trip(90) }), is_shown))
    end)

    it("gives back nothing once the drawing has gone", function()
      -- Expired, or replaced by another highlight
      assert.is_nil(trip_view.shown(watching(1, 1, GONE), a_network(1, { a_trip(90) }), is_shown))
    end)

    it("gives back nothing for a trip shown in another network", function()
      -- The player moved into a network that happens to carry the same item. Offering to stop
      -- listing one of its trips would exclude a trip they never looked at
      local elsewhere = a_network(2, { a_trip(90), a_trip(80), a_trip(70) })
      assert.is_nil(trip_view.shown(watching(1, 3), elsewhere, is_shown))
      assert.is_nil(trip_view.shown(watching(1, 3), nil, is_shown))
    end)

    it("gives back nothing for a view saved before the network was recorded", function()
      local old = { trip_view = { key = IRON, index = 1, object_id = DRAWN } }
      assert.is_nil(trip_view.shown(old, a_network(1, { a_trip(90) }), is_shown))
    end)

    it("gives back nothing when the list has shrunk under the shown trip", function()
      -- Another player ignoring a trip removes it from the shared history
      assert.is_nil(trip_view.shown(watching(1, 3), a_network(1, { a_trip(90), a_trip(80) }), is_shown))
    end)

    it("gives back nothing when the item has left the history", function()
      -- Someone cleared the history while the drawing was still up
      assert.is_nil(trip_view.shown(watching(1, 1), { id = 1, delivery_history = {} }, is_shown))
      assert.is_nil(trip_view.shown(watching(1, 1), { id = 1 }, is_shown))
    end)

    it("gives back nothing for an item with no trips left", function()
      assert.is_nil(trip_view.shown(watching(1, 1), a_network(1, {}), is_shown))
      assert.is_nil(trip_view.shown(watching(1, 1), a_network(1, nil), is_shown))
    end)
  end)
end)
