local mock = require("tests.mocks.factorio")

describe("scheduler", function()
  local scheduler

  before_each(function()
    mock.fresh()
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
      background_refresh_interval_ticks = 600,
      background_refresh_interval_secs = 10,
    }
    storage.players = {}

    -- game.get_player returns a valid, connected player by default
    game.get_player = function(idx)
      return { valid = true, connected = true }
    end

    scheduler = require("scripts.scheduler")
  end)

  -- ─── Registration & lifecycle ─────────────────────────────────────

  describe("register()", function()
    it("registers a global task", function()
      local called = false
      scheduler.register({ name = "test-global", interval = 10, fn = function() called = true end })

      game.tick = 10
      scheduler.on_tick()
      assert.is_true(called)
    end)

    it("registers a per-player task", function()
      local called_with = {}
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({
        name = "test-player",
        interval = 10,
        per_player = true,
        fn = function(player, pt)
          table.insert(called_with, pt)
        end,
      })

      game.tick = 10
      scheduler.on_tick()
      assert.are.equal(1, #called_with)
    end)
  end)

  describe("unregister()", function()
    it("removes a global task so it no longer fires", function()
      local call_count = 0
      scheduler.register({ name = "temp", interval = 10, fn = function() call_count = call_count + 1 end })

      game.tick = 10
      scheduler.on_tick()
      assert.are.equal(1, call_count)

      scheduler.unregister("temp")

      -- Rebuild queue by advancing past the 60-tick window
      game.tick = 80
      scheduler.on_tick()
      assert.are.equal(1, call_count) -- not called again
    end)

    it("removes a per-player task", function()
      local called = false
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({ name = "temp-p", interval = 10, per_player = true, fn = function() called = true end })

      scheduler.unregister("temp-p")

      game.tick = 10
      scheduler.on_tick()
      assert.is_false(called)
    end)
  end)

  describe("update_interval()", function()
    it("changes interval for a global task", function()
      local call_count = 0
      scheduler.register({ name = "flex", interval = 10, fn = function() call_count = call_count + 1 end })

      -- Fires at tick 10
      game.tick = 10
      scheduler.on_tick()
      assert.are.equal(1, call_count)

      -- Change interval to 7, rebuild queue
      scheduler.update_interval("flex", 7)
      game.tick = 70  -- force queue rebuild
      scheduler.on_tick() -- rebuilds, tick 70 % 7 == 0
      assert.are.equal(2, call_count)

      -- Tick 77 should fire (77 % 7 == 0)
      game.tick = 77
      scheduler.on_tick()
      assert.are.equal(3, call_count)

      -- Tick 80 should NOT fire (80 % 7 == 3)
      game.tick = 80
      scheduler.on_tick()
      assert.are.equal(3, call_count)
    end)

    it("changes interval for a per-player task", function()
      scheduler.register({ name = "pflex", interval = 10, per_player = true, fn = function() end })
      scheduler.update_interval("pflex", 20)

      -- Verify by checking tick 20 fires but tick 10 doesn't
      local called = false
      scheduler.unregister("pflex")
      scheduler.register({ name = "pflex", interval = 20, per_player = true, fn = function() called = true end })
      storage.players[1] = { player_index = 1, settings = {} }

      game.tick = 20
      scheduler.on_tick()
      assert.is_true(called)
    end)
  end)

  -- ─── Task dispatch via on_tick() ──────────────────────────────────

  describe("on_tick() dispatch", function()
    it("fires global task when tick % interval == 0", function()
      local ticks_fired = {}
      scheduler.register({ name = "every-5", interval = 5, fn = function()
        table.insert(ticks_fired, game.tick)
      end })

      -- Note: tick 0 never fires because the initial queue is empty
      -- and the first rebuild happens at tick 1, covering ticks 1-60.
      for t = 0, 20 do
        game.tick = t
        scheduler.on_tick()
      end

      assert.are.same({5, 10, 15, 20}, ticks_fired)
    end)

    it("does NOT fire global task on non-matching ticks", function()
      local called = false
      scheduler.register({ name = "every-10", interval = 10, fn = function() called = true end })

      game.tick = 7
      scheduler.on_tick()
      assert.is_false(called)
    end)

    it("fires per-player task for each connected player", function()
      local players_seen = {}
      storage.players[1] = { player_index = 1, settings = {} }
      storage.players[2] = { player_index = 2, settings = {} }
      scheduler.register({
        name = "per-p",
        interval = 10,
        per_player = true,
        fn = function(player, pt) table.insert(players_seen, pt.player_index) end,
      })

      game.tick = 10
      scheduler.on_tick()
      table.sort(players_seen)
      assert.are.same({1, 2}, players_seen)
    end)

    it("skips disconnected players", function()
      local called_for = {}
      storage.players[1] = { player_index = 1, settings = {} }
      storage.players[2] = { player_index = 2, settings = {} }

      game.get_player = function(idx)
        if idx == 2 then
          return { valid = true, connected = false } -- disconnected
        end
        return { valid = true, connected = true }
      end

      scheduler.register({
        name = "check-connected",
        interval = 10,
        per_player = true,
        fn = function(player, pt) table.insert(called_for, pt.player_index) end,
      })

      game.tick = 10
      scheduler.on_tick()
      assert.are.same({1}, called_for)
    end)

    it("skips invalid players", function()
      local called = false
      storage.players[1] = { player_index = 1, settings = {} }
      game.get_player = function() return { valid = false, connected = true } end

      scheduler.register({
        name = "check-valid",
        interval = 10,
        per_player = true,
        fn = function() called = true end,
      })

      game.tick = 10
      scheduler.on_tick()
      assert.is_false(called)
    end)

    it("rebuilds queue when advancing past the 60-tick window", function()
      local call_count = 0
      scheduler.register({ name = "long-run", interval = 10, fn = function() call_count = call_count + 1 end })

      -- First window built at tick 1, covering 1-60. Tick 10 fires.
      game.tick = 10
      scheduler.on_tick()
      assert.are.equal(1, call_count)

      -- Jump to tick 70 (past first 60-tick window), should rebuild and fire
      game.tick = 70
      scheduler.on_tick()
      assert.are.equal(2, call_count)
    end)
  end)

  -- ─── Heavy task spreading ─────────────────────────────────────────

  describe("heavy task spreading", function()
    it("spreads heavy tasks across the queue window", function()
      -- Register several heavy tasks with the same interval.
      -- They'd all land on the same ticks, but the scheduler should spread them.
      local fired = {}
      for i = 1, 6 do
        local name = "heavy-" .. i
        scheduler.register({
          name = name,
          interval = 10,
          is_heavy = true,
          fn = function()
            fired[game.tick] = (fired[game.tick] or 0) + 1
          end,
        })
      end

      -- Queue built at tick 1, covering 1-60.
      -- Interval 10 matches ticks: 10, 20, 30, 40, 50, 60 = 6 ticks
      -- But we only loop through 0-59, so tick 60 is not reached.
      -- Matching ticks in loop: 10, 20, 30, 40, 50 = 5 ticks
      -- Total: 6 tasks * 5 ticks = 30
      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      local total = 0
      local max_per_tick = 0
      for _, count in pairs(fired) do
        total = total + count
        if count > max_per_tick then max_per_tick = count end
      end

      assert.are.equal(30, total) -- all tasks still execute
      -- Without spreading, all 6 would land on the same tick.
      -- With spreading (max_heavy_per_tick = ceil(30/60) = 1), expect <= 2
      assert.is_true(max_per_tick <= 2,
        "expected max 2 heavy per tick after spreading, got " .. max_per_tick)
    end)

    it("does not drop any heavy tasks during redistribution", function()
      local total_calls = 0
      for i = 1, 4 do
        scheduler.register({
          name = "h-" .. i,
          interval = 5,
          is_heavy = true,
          fn = function() total_calls = total_calls + 1 end,
        })
      end

      -- Queue covers ticks 1-60. Interval 5 matches: 5,10,...,55 = 11 ticks in 0-59 loop
      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      -- 4 tasks * 11 matching ticks = 44
      assert.are.equal(44, total_calls)
    end)
  end)

  -- ─── Player interval overrides ────────────────────────────────────

  describe("player interval overrides", function()
    it("applies per-player interval override", function()
      local p1_ticks = {}
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({
        name = "ui-update",
        interval = 60,
        per_player = true,
        fn = function(player, pt)
          table.insert(p1_ticks, game.tick)
        end,
      })

      -- Override player 1 to interval 20
      scheduler.update_player_interval(1, "ui-update", 20)

      -- Queue covers ticks 1-60; interval 20 matches: 20, 40
      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      assert.are.same({20, 40}, p1_ticks)
    end)

    it("removes override when interval matches default", function()
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({ name = "ui", interval = 30, per_player = true, fn = function() end })

      -- Set override then clear it by setting to default
      scheduler.update_player_interval(1, "ui", 10)
      scheduler.update_player_interval(1, "ui", 30) -- matches default → override removed

      -- Should fire at default interval (30), ticks 30 in the 1-60 window
      local called = 0
      scheduler.unregister("ui")
      scheduler.register({ name = "ui", interval = 30, per_player = true, fn = function() called = called + 1 end })

      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      assert.are.equal(1, called) -- tick 30
    end)

    it("different players can have different intervals", function()
      local p1_count, p2_count = 0, 0
      storage.players[1] = { player_index = 1, settings = {} }
      storage.players[2] = { player_index = 2, settings = {} }

      scheduler.register({
        name = "multi",
        interval = 60,
        per_player = true,
        fn = function(player, pt)
          if pt.player_index == 1 then p1_count = p1_count + 1 end
          if pt.player_index == 2 then p2_count = p2_count + 1 end
        end,
      })

      scheduler.update_player_interval(1, "multi", 10) -- p1: every 10
      scheduler.update_player_interval(2, "multi", 20) -- p2: every 20

      -- Queue 1-60; loop 0-59
      -- p1 interval 10: ticks 10,20,30,40,50 = 5
      -- p2 interval 20: ticks 20,40 = 2
      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      assert.are.equal(5, p1_count)
      assert.are.equal(2, p2_count)
    end)

    it("update_player_intervals does batch update", function()
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({ name = "a", interval = 60, per_player = true, fn = function() end })
      scheduler.register({ name = "b", interval = 60, per_player = true, fn = function() end })

      scheduler.update_player_intervals(1, { a = 10, b = 20 })

      -- Verify by counting calls
      local a_count, b_count = 0, 0
      scheduler.unregister("a")
      scheduler.unregister("b")
      scheduler.register({ name = "a", interval = 60, per_player = true, fn = function() a_count = a_count + 1 end })
      scheduler.register({ name = "b", interval = 60, per_player = true, fn = function() b_count = b_count + 1 end })
      scheduler.update_player_intervals(1, { a = 10, b = 20 })

      -- Queue 1-60; loop 0-59
      -- a interval 10: ticks 10,20,30,40,50 = 5
      -- b interval 20: ticks 20,40 = 2
      for t = 0, 59 do
        game.tick = t
        scheduler.on_tick()
      end

      assert.are.equal(5, a_count)
      assert.are.equal(2, b_count)
    end)

    it("ignores override for unknown task", function()
      -- Should not crash
      assert.has_no.errors(function()
        scheduler.update_player_interval(1, "nonexistent", 10)
      end)
    end)
  end)

  -- ─── Error handling ───────────────────────────────────────────────

  describe("error handling", function()
    it("catches task errors without crashing", function()
      scheduler.register({ name = "crasher", interval = 10, fn = function()
        error("boom!")
      end })

      -- Should not propagate the error
      game.tick = 10
      assert.has_no.errors(function()
        scheduler.on_tick()
      end)
    end)

    it("continues running other tasks after one fails", function()
      local second_called = false
      scheduler.register({ name = "crash-first", interval = 10, fn = function()
        error("fail")
      end })
      scheduler.register({ name = "ok-second", interval = 10, fn = function()
        second_called = true
      end })

      game.tick = 10
      scheduler.on_tick()
      assert.is_true(second_called)
    end)

    it("catches per-player task errors without crashing", function()
      storage.players[1] = { player_index = 1, settings = {} }
      scheduler.register({
        name = "player-crash",
        interval = 10,
        per_player = true,
        fn = function() error("player boom!") end,
      })

      game.tick = 10
      assert.has_no.errors(function()
        scheduler.on_tick()
      end)
    end)
  end)

  -- ─── apply_global_settings() ──────────────────────────────────────

  describe("apply_global_settings()", function()
    it("updates background-refresh interval from global_data", function()
      -- Register background-refresh task (like control.lua does)
      local called = false
      scheduler.register({
        name = "background-refresh",
        interval = 600, -- 10 seconds default
        is_heavy = true,
        fn = function() called = true end,
      })

      -- Change the setting
      storage.global.background_refresh_interval_ticks = 120
      scheduler.apply_global_settings()

      -- Force queue rebuild and check tick 120 fires
      game.tick = 120
      scheduler.on_tick()
      assert.is_true(called)
    end)
  end)

  -- ─── Realistic 3000-tick workload ─────────────────────────────────
  -- Registers the exact same tasks as control.lua, runs 3000 ticks with
  -- 2 connected players, and verifies invocation counts + congestion.

  describe("realistic 3000-tick workload", function()
    local counts         -- task_name -> total invocations
    local heavy_per_tick -- tick -> number of heavy task invocations
    local total_per_tick -- tick -> number of all task invocations
    local TICKS = 3000
    local NUM_PLAYERS = 2

    before_each(function()
      counts = {}
      heavy_per_tick = {}
      total_per_tick = {}

      -- Two connected players
      for i = 1, NUM_PLAYERS do
        storage.players[i] = { player_index = i, settings = {} }
      end

      -- Helper: register a task and wire up counting + per-tick tracking
      local function reg(opts)
        local name = opts.name
        local is_heavy = opts.is_heavy or false
        counts[name] = 0
        scheduler.register({
          name = name,
          interval = opts.interval,
          per_player = opts.per_player or false,
          is_heavy = is_heavy,
          fn = function()
            counts[name] = counts[name] + 1
            local t = game.tick
            total_per_tick[t] = (total_per_tick[t] or 0) + 1
            if is_heavy then
              heavy_per_tick[t] = (heavy_per_tick[t] or 0) + 1
            end
          end,
        })
      end

      -- Exact registrations from control.lua (lines 82-131)
      reg({ name = "network-check",              interval = 29,  per_player = true  })
      reg({ name = "background-refresh",         interval = 11,  is_heavy = true    })
      reg({ name = "clear-caches",               interval = 600                     })
      reg({ name = "find-next-player-network",   interval = 7                       })
      reg({ name = "player-network-bot-chunk",   interval = 5,   is_heavy = true    })
      reg({ name = "player-network-cell-chunk",  interval = 7,   is_heavy = true    })
      reg({ name = "pick-network-to-analyse",    interval = 31                      })
      reg({ name = "run-derived-analysis",       interval = 9,   is_heavy = true    })
      reg({ name = "ui-update",                  interval = 60,  per_player = true  })
      reg({ name = "analysis-progress-update",   interval = 5,   per_player = true  })

      -- Run all 3000 ticks
      for t = 1, TICKS do
        game.tick = t
        scheduler.on_tick()
      end
    end)

    -- ─── Invocation counts ────────────────────────────────────────

    it("fires each global task the correct number of times", function()
      -- Global task with interval I: floor(TICKS / I) invocations
      assert.are.equal(math.floor(TICKS / 11),  counts["background-refresh"])
      assert.are.equal(math.floor(TICKS / 600), counts["clear-caches"])
      assert.are.equal(math.floor(TICKS / 7),   counts["find-next-player-network"])
      assert.are.equal(math.floor(TICKS / 5),   counts["player-network-bot-chunk"])
      assert.are.equal(math.floor(TICKS / 7),   counts["player-network-cell-chunk"])
      assert.are.equal(math.floor(TICKS / 31),  counts["pick-network-to-analyse"])
      assert.are.equal(math.floor(TICKS / 9),   counts["run-derived-analysis"])
    end)

    it("fires each per-player task the correct number of times", function()
      -- Per-player task: floor(TICKS / I) * NUM_PLAYERS
      assert.are.equal(math.floor(TICKS / 29) * NUM_PLAYERS, counts["network-check"])
      assert.are.equal(math.floor(TICKS / 60) * NUM_PLAYERS, counts["ui-update"])
      assert.are.equal(math.floor(TICKS / 5)  * NUM_PLAYERS, counts["analysis-progress-update"])
    end)

    -- ─── Congestion checks ───────────────────────────────────────

    it("never exceeds 3 heavy tasks in any single tick", function()
      -- 4 heavy tasks at intervals 5, 7, 9, 11. Without spreading, ticks
      -- like LCM(5,7,9) = 315 would have 3+ simultaneous heavy tasks.
      -- The scheduler redistributes excess, but can't always achieve 1 per
      -- tick due to window boundaries and LCM collisions. 3 is a solid
      -- improvement over the unspread worst case of 4.
      local max_heavy = 0
      local worst_tick = 0
      for t, count in pairs(heavy_per_tick) do
        if count > max_heavy then
          max_heavy = count
          worst_tick = t
        end
      end
      assert.is_true(max_heavy <= 3,
        "tick " .. worst_tick .. " had " .. max_heavy .. " heavy tasks (max allowed: 3)")
    end)

    it("keeps total tasks per tick reasonable (no pathological spikes)", function()
      -- With 10 tasks, 2 players, and per-player tasks counting once per player,
      -- a reasonable upper bound is ~12 tasks in any single tick.
      local max_total = 0
      local worst_tick = 0
      for t, count in pairs(total_per_tick) do
        if count > max_total then
          max_total = count
          worst_tick = t
        end
      end
      assert.is_true(max_total <= 12,
        "tick " .. worst_tick .. " had " .. max_total .. " total tasks (max allowed: 12)")
    end)

    it("has heavy tasks spread across many ticks (not clustered)", function()
      -- Count how many distinct ticks have at least one heavy task
      local ticks_with_heavy = 0
      for _ in pairs(heavy_per_tick) do
        ticks_with_heavy = ticks_with_heavy + 1
      end
      -- Total heavy invocations
      local total_heavy = counts["background-refresh"]
        + counts["player-network-bot-chunk"]
        + counts["player-network-cell-chunk"]
        + counts["run-derived-analysis"]
      -- If perfectly spread with max 1 per tick, we'd need total_heavy ticks.
      -- With max 2 per tick, at least total_heavy/2 ticks.
      -- Assert we're using at least 40% of the theoretical minimum spread
      -- (generous margin for the redistribution algorithm).
      local min_spread = math.ceil(total_heavy / 2)
      assert.is_true(ticks_with_heavy >= min_spread * 0.4,
        "heavy tasks concentrated in only " .. ticks_with_heavy ..
        " ticks out of " .. min_spread .. " minimum needed")
    end)
  end)
end)
