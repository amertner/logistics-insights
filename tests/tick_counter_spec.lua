local mock = require("tests.mocks.factorio")

describe("TickCounter", function()
  local TickCounter

  before_each(function()
    mock.fresh()
    game.tick = 0
    TickCounter = require("scripts.tick-counter")
  end)

  -- ─── Construction ────────────────────────────────────────��────────

  describe("new()", function()
    it("creates a running counter starting at current tick", function()
      game.tick = 100
      local tc = TickCounter.new()
      assert.is_false(tc:is_paused())
      assert.are.equal(0, tc:elapsed())
    end)

    it("accepts an explicit initial tick", function()
      game.tick = 200
      local tc = TickCounter.new(150)
      -- elapsed = game.tick - start_tick = 200 - 150 = 50
      assert.are.equal(50, tc:elapsed())
    end)
  end)

  -- ─── Elapsed time ─────────────────────────────────────────────────

  describe("elapsed()", function()
    it("tracks time while running", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      assert.are.equal(100, tc:elapsed())
      game.tick = 250
      assert.are.equal(250, tc:elapsed())
    end)

    it("freezes when paused", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      game.tick = 500
      assert.are.equal(100, tc:elapsed())
    end)

    it("accumulates across pause/resume cycles", function()
      game.tick = 0
      local tc = TickCounter.new()

      -- Run for 100 ticks
      game.tick = 100
      tc:pause()
      assert.are.equal(100, tc:elapsed())

      -- Paused for 50 ticks (should not count)
      game.tick = 150
      tc:resume()

      -- Run for another 60 ticks
      game.tick = 210
      assert.are.equal(160, tc:elapsed()) -- 100 + 60

      -- Pause again
      tc:pause()
      game.tick = 1000
      assert.are.equal(160, tc:elapsed()) -- still 160
    end)

    it("accumulates across many cycles", function()
      game.tick = 0
      local tc = TickCounter.new()

      -- Each cycle: run 50 ticks, pause 50 ticks
      for i = 1, 5 do
        game.tick = i * 100 - 50   -- pause after 50 running ticks
        tc:pause()
        game.tick = i * 100        -- resume after 50 paused ticks
        tc:resume()
      end

      -- 5 cycles * 50 ticks running = 250 accumulated
      game.tick = 500 + 30  -- 30 more running ticks after last resume
      assert.are.equal(280, tc:elapsed()) -- 250 + 30
    end)
  end)

  -- ─── current_elapsed() ��───────────────────────────────────────────

  -- ─── time_since_paused() ──────────────────────────────────────────

  -- ─── Pause / Resume ───────────────────────────────────────────────

  describe("pause()", function()
    it("returns true on first pause", function()
      local tc = TickCounter.new()
      assert.is_true(tc:pause())
      assert.is_true(tc:is_paused())
    end)

    it("returns false if already paused (idempotent)", function()
      local tc = TickCounter.new()
      tc:pause()
      assert.is_false(tc:pause())
    end)

    it("does not change elapsed time on double-pause", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      local elapsed1 = tc:elapsed()
      game.tick = 200
      tc:pause() -- no-op
      assert.are.equal(elapsed1, tc:elapsed())
    end)
  end)

  describe("resume()", function()
    it("returns true on resume from paused", function()
      local tc = TickCounter.new()
      tc:pause()
      assert.is_true(tc:resume())
      assert.is_false(tc:is_paused())
    end)

    it("returns false if already running (idempotent)", function()
      local tc = TickCounter.new()
      assert.is_false(tc:resume())
    end)
  end)

  -- ─── Toggle ───────────────────────────────────────────────────────

  -- ─── set_paused() ─────────────────────────────────────────────────

  -- ─── Reset ────────────────────────────────────────────────────────

  describe("reset()", function()
    it("clears all state and starts running", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      game.tick = 200

      tc:reset()
      assert.is_false(tc:is_paused())
      assert.are.equal(0, tc:elapsed())
      game.tick = 250
      assert.are.equal(50, tc:elapsed())
    end)

    it("clears accumulated time from previous cycles", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      game.tick = 150
      tc:resume()
      game.tick = 200

      tc:reset()
      assert.are.equal(0, tc:elapsed())
    end)
  end)

  describe("reset_keep_pause()", function()
    it("resets time but keeps paused state", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      game.tick = 200

      tc:reset_keep_pause()
      assert.is_true(tc:is_paused())
      assert.are.equal(0, tc:elapsed())
    end)

    it("resets time but keeps running state", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100

      tc:reset_keep_pause()
      assert.is_false(tc:is_paused())
      assert.are.equal(0, tc:elapsed())
      game.tick = 130
      assert.are.equal(30, tc:elapsed())
    end)
  end)

  -- ─── total_unpaused() ─────────────────────────────────────────────

  describe("total_unpaused()", function()
    it("is an alias for elapsed()", function()
      game.tick = 0
      local tc = TickCounter.new()
      game.tick = 100
      tc:pause()
      game.tick = 200
      tc:resume()
      game.tick = 250
      assert.are.equal(tc:elapsed(), tc:total_unpaused())
    end)
  end)

  -- ─── to_string() ──────────────────────────────────────────────────

end)
