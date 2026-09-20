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
end)
