local mock = require("tests.mocks.factorio")

describe("sorted-item-row", function()
  local sorted_item_row
  local ROW, MAX = "totals-row", 3

  before_each(function()
    mock.fresh()
    -- Tooltips localise the item and its quality. Every 2.0 game has normal quality, and utils
    -- reads it without a guard, so the mock needs it to stand in for one
    prototypes.quality["normal"] = { localised_name = "Normal" }
    prototypes.item["iron-plate"] = { localised_name = "Iron plate" }
    prototypes.item["copper-plate"] = { localised_name = "Copper plate" }
    sorted_item_row = require("scripts.mainwin.sorted_item_row")
  end)

  -- The row draws into sprite-buttons. These stand in for them and count every property written,
  -- so a redraw that writes the same nothing twice can be told from one that is skipped
  local function a_row(count)
    local counter = { writes = 0 }
    local cells = {}
    for i = 1, count do
      local store = { valid = true }
      cells[i] = setmetatable({}, {
        __index = store,
        __newindex = function(_, k, v) counter.writes = counter.writes + 1 store[k] = v end,
      })
    end
    return cells, counter
  end

  local function a_player(cells)
    return { settings = { max_items = MAX }, ui = { [ROW] = cells and { cells = cells } or {} } }
  end

  local function some_items()
    return {
      ["iron-plate|normal"] = { item_name = "iron-plate", quality_name = "normal", count = 10 },
      ["copper-plate|normal"] = { item_name = "copper-plate", quality_name = "normal", count = 4 },
    }
  end

  local by_count = function(a, b) return a.count > b.count end

  local function draw(player_table, generation)
    sorted_item_row.update(player_table, ROW, some_items(), by_count, "count", nil, generation)
  end

  it("draws the items in order and blanks the rest of the row", function()
    local cells = a_row(MAX)
    draw(a_player(cells), 1)
    assert.are.equal(10, cells[1].number)
    assert.is_true(cells[1].enabled)
    assert.are.equal(4, cells[2].number)
    assert.is_nil(cells[3].number)
    assert.is_false(cells[3].enabled)
  end)

  it("skips an update on the generation it last drew", function()
    local cells, counter = a_row(MAX)
    local player_table = a_player(cells)
    draw(player_table, 1)
    local drawn = counter.writes
    draw(player_table, 1)
    assert.are.equal(drawn, counter.writes)
    draw(player_table, 2)
    assert.is_true(counter.writes > drawn)
  end)

  describe("clear_cells()", function()
    it("blanks every cell it had drawn into", function()
      local cells = a_row(MAX)
      local player_table = a_player(cells)
      draw(player_table, 1)
      sorted_item_row.clear_cells(player_table, ROW)
      assert.is_nil(cells[1].number)
      assert.is_false(cells[1].enabled)
      assert.are.equal("", cells[1].sprite)
    end)

    it("costs nothing once the row is already blank", function()
      -- A row with no network to draw from is cleared on every UI update, for as long as the
      -- player stands outside one
      local cells, counter = a_row(MAX)
      local player_table = a_player(cells)
      sorted_item_row.clear_cells(player_table, ROW)
      local cleared = counter.writes
      assert.is_true(cleared > 0)
      for _ = 1, 5 do
        sorted_item_row.clear_cells(player_table, ROW)
      end
      assert.are.equal(cleared, counter.writes)
    end)

    it("does not let the next update be skipped", function()
      -- The row no longer shows what that generation held, even though the data has not moved on
      local cells = a_row(MAX)
      local player_table = a_player(cells)
      draw(player_table, 1)
      sorted_item_row.clear_cells(player_table, ROW)
      draw(player_table, 1)
      assert.are.equal(10, cells[1].number)
    end)
  end)

  it("does not remember a generation it had nowhere to draw", function()
    -- Recording it before drawing would leave the row blank until the data changed again
    local player_table = a_player(nil)
    draw(player_table, 1)

    local cells = a_row(MAX)
    player_table.ui[ROW].cells = cells
    draw(player_table, 1)
    assert.are.equal(10, cells[1].number)
  end)
end)
