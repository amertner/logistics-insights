local mock = require("tests.mocks.factorio")

describe("bot_counter", function()
  local bot_counter, chunker_mod

  before_each(function()
    mock.fresh()
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
    }
    storage.networks = {}

    -- Set up a quality chain so bot_chunks_done can compute totals
    prototypes.quality.normal = { name = "normal", next = { name = "uncommon", next = { name = "rare", next = nil } } }

    chunker_mod = require("scripts.chunker")
    bot_counter = require("scripts.bot-counter")
  end)

  -- ─── Helpers ──────────────────────────────────────────────────────

  --- Create a minimal networkdata with a real bot_chunker
  local function make_networkdata(id)
    local nwd = {
      id = id or 1,
      bot_chunker = chunker_mod.new(),
      bot_items = {},
      bot_deliveries = {},
      bot_active_deliveries = {},
      delivery_history = {},
      last_pass_bots_seen = {},
      last_scanned_tick = 0,
      players_set = {},
      idle_bot_qualities = {},
      picking_bot_qualities = {},
      delivering_bot_qualities = {},
      other_bot_qualities = {},
      total_bot_qualities = {},
    }
    storage.networks[nwd.id] = nwd
    return nwd
  end

  --- Create a mock bot entity
  local function make_bot(opts)
    opts = opts or {}
    return {
      valid = opts.valid ~= false,
      unit_number = opts.unit_number,
      quality = opts.quality or { name = "normal" },
      robot_order_queue = opts.orders or {},
    }
  end

  --- Create a deliver order
  local function deliver_order(item_name, count, opts)
    opts = opts or {}
    local quality_name = opts.quality or "normal"
    local target_pos = opts.target_pos or { x = 0, y = 0 }
    return {
      type = defines.robot_order_type.deliver,
      target_item = {
        name = { name = item_name },
        quality = { name = quality_name },
      },
      target_count = count,
      target = { position = target_pos },
    }
  end

  --- Create a pickup order
  local function pickup_order(item_name)
    return {
      type = defines.robot_order_type.pickup,
      target_item = {
        name = { name = item_name },
        quality = { name = "normal" },
      },
      target_count = 0,
    }
  end

  --- Create a mock LuaLogisticNetwork
  local function make_network(bots)
    return {
      valid = true,
      logistic_robots = bots,
    }
  end

  --- Drive chunker to completion via public API
  local function run_chunker(nwd)
    if nwd.bot_chunker.state == "fetching" then
      bot_counter.process_next_chunk(nwd)
    end
    while not bot_counter.is_scanning_done(nwd) do
      bot_counter.process_next_chunk(nwd)
    end
  end

  --- Process via background mode (no history tracking)
  local function process_all(nwd, bots)
    bot_counter.init_background_processing(nwd, make_network(bots))
    run_chunker(nwd)
  end

  --- Process via foreground mode (with history tracking)
  --- Sets up a mock player with show_history=true
  local function process_all_foreground(nwd, bots)
    nwd.players_set = { [1] = true }
    storage.players = { [1] = { settings = { show_history = true } } }
    bot_counter.init_foreground_processing(nwd, make_network(bots))
    run_chunker(nwd)
  end

  -- ─── Bot classification ───────────────────────────────────────────

  describe("bot classification", function()
    it("counts delivering bots", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("copper-plate", 30) } }),
        make_bot({ unit_number = 3 }), -- idle
      }

      process_all(nwd, bots)
      assert.are.equal(2, nwd.bot_items["delivering"])
    end)

    it("counts picking bots", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { pickup_order("iron-plate") } }),
        make_bot({ unit_number = 2, orders = { pickup_order("copper-plate") } }),
      }

      process_all(nwd, bots)
      assert.are.equal(2, nwd.bot_items["picking"])
    end)

    it("does not count idle bots as delivering or picking", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1 }),
        make_bot({ unit_number = 2 }),
      }

      process_all(nwd, bots)
      assert.are.equal(0, nwd.bot_items["delivering"])
      assert.are.equal(0, nwd.bot_items["picking"])
    end)

    it("classifies a mix of bot types correctly", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10) } }),
        make_bot({ unit_number = 2, orders = { pickup_order("copper-plate") } }),
        make_bot({ unit_number = 3 }), -- idle
        make_bot({ unit_number = 4, orders = { deliver_order("steel-plate", 5) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(2, nwd.bot_items["delivering"])
      assert.are.equal(1, nwd.bot_items["picking"])
    end)
  end)

  -- ─── Current delivery tracking ────────────────────────────────────

  describe("current delivery tracking", function()
    it("records items being delivered", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("iron-plate", 30) } }),
      }

      process_all(nwd, bots)
      local delivery = nwd.bot_deliveries["iron-plate:normal"]
      assert.is_not_nil(delivery)
      assert.are.equal("iron-plate", delivery.item_name)
      assert.are.equal(80, delivery.count) -- 50 + 30
    end)

    it("tracks different items separately", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("copper-plate", 20) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(50, nwd.bot_deliveries["iron-plate:normal"].count)
      assert.are.equal(20, nwd.bot_deliveries["copper-plate:normal"].count)
    end)

    it("tracks quality variants separately", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { quality = "normal" }) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("iron-plate", 30, { quality = "uncommon" }) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(50, nwd.bot_deliveries["iron-plate:normal"].count)
      assert.are.equal(30, nwd.bot_deliveries["iron-plate:uncommon"].count)
    end)
  end)

  -- ─── Quality tracking ─────────────────────────────────────────────

  describe("quality tracking", function()
    it("accumulates delivering bot qualities", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, quality = { name = "normal" }, orders = { deliver_order("iron-plate", 10) } }),
        make_bot({ unit_number = 2, quality = { name = "uncommon" }, orders = { deliver_order("iron-plate", 10) } }),
        make_bot({ unit_number = 3, quality = { name = "normal" }, orders = { deliver_order("iron-plate", 10) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(2, nwd.delivering_bot_qualities["normal"])
      assert.are.equal(1, nwd.delivering_bot_qualities["uncommon"])
    end)

    it("accumulates picking bot qualities", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, quality = { name = "rare" }, orders = { pickup_order("x") } }),
      }

      process_all(nwd, bots)
      assert.are.equal(1, nwd.picking_bot_qualities["rare"])
    end)

    it("accumulates idle bot qualities as other", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, quality = { name = "normal" } }),
        make_bot({ unit_number = 2, quality = { name = "normal" } }),
      }

      process_all(nwd, bots)
      assert.are.equal(2, nwd.other_bot_qualities["normal"])
    end)

    it("computes total qualities across all categories", function()
      local nwd = make_networkdata()
      nwd.idle_bot_qualities = { normal = 5 }
      local bots = {
        make_bot({ unit_number = 1, quality = { name = "normal" }, orders = { deliver_order("x", 1) } }),
        make_bot({ unit_number = 2, quality = { name = "normal" }, orders = { pickup_order("y") } }),
        make_bot({ unit_number = 3, quality = { name = "normal" } }),
      }

      process_all(nwd, bots)
      -- idle(5) + delivering(1) + picking(1) + other(1) = 8
      assert.are.equal(8, nwd.total_bot_qualities["normal"])
    end)

    it("skips quality tracking when gather_quality_data is disabled", function()
      storage.global.gather_quality_data = false
      mock.unload("scripts.")
      chunker_mod = require("scripts.chunker")
      bot_counter = require("scripts.bot-counter")

      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = 1, quality = { name = "normal" }, orders = { deliver_order("x", 1) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(1, nwd.bot_items["delivering"])
      -- Quality tables should be empty since gathering was disabled
      assert.is_nil(nwd.delivering_bot_qualities["normal"])
    end)
  end)

  -- ─── Delivery history tracking ────────────────────────────────────

  describe("delivery history", function()
    it("records completed delivery in history when bot stops delivering", function()
      local nwd = make_networkdata()
      game.tick = 100

      -- Pass 1: bot is delivering (foreground so history is tracked)
      local delivering_bot = make_bot({
        unit_number = 1,
        orders = { deliver_order("iron-plate", 50, { target_pos = { x = 10, y = 20 } }) },
      })
      process_all_foreground(nwd, { delivering_bot })

      -- Delivery should be tracked as active
      assert.is_not_nil(nwd.bot_active_deliveries[1])

      -- Pass 2: same bot is now idle (delivery completed)
      game.tick = 200
      local idle_bot = make_bot({ unit_number = 1 })
      process_all_foreground(nwd, { idle_bot })

      -- History should have the delivery
      local history = nwd.delivery_history["iron-plate:normal"]
      assert.is_not_nil(history)
      assert.are.equal("iron-plate", history.item_name)
      assert.are.equal(50, history.count)
    end)

    it("records delivery when bot changes target (works in background mode)", function()
      local nwd = make_networkdata()
      game.tick = 100

      -- Pass 1: bot delivering to position A
      local bot_pass1 = make_bot({
        unit_number = 1,
        orders = { deliver_order("iron-plate", 50, { target_pos = { x = 10, y = 20 } }) },
      })
      process_all(nwd, { bot_pass1 })

      -- Pass 2: same bot delivering to position B (new target)
      -- Target change records history directly in add_bot_to_active_deliveries,
      -- bypassing the show_history check, so this works in background mode.
      game.tick = 200
      local bot_pass2 = make_bot({
        unit_number = 1,
        orders = { deliver_order("iron-plate", 30, { target_pos = { x = 99, y = 99 } }) },
      })
      process_all(nwd, { bot_pass2 })

      -- First delivery should be in history (target changed)
      local history = nwd.delivery_history["iron-plate:normal"]
      assert.is_not_nil(history)
      assert.are.equal(50, history.count) -- first delivery's count
    end)

    it("accumulates history across multiple completed deliveries", function()
      local nwd = make_networkdata()

      -- Delivery 1
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { target_pos = { x = 1, y = 1 } }) } }),
      })
      game.tick = 200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) }) -- idle = delivery done

      -- Delivery 2
      game.tick = 300
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 30, { target_pos = { x = 2, y = 2 } }) } }),
      })
      game.tick = 400
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) }) -- idle = delivery done

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.is_not_nil(history)
      assert.are.equal(80, history.count) -- 50 + 30
    end)

    it("computes average delivery time", function()
      local nwd = make_networkdata()

      -- Pass 1 (tick 1000): bot starts delivering — first_seen = 1000
      game.tick = 1000
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
      })

      -- Pass 2 (tick 1100): bot still delivering same target — last_seen updated to 1100
      game.tick = 1100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
      })

      -- Pass 3 (tick 1200): bot idle — delivery completed, recorded in history
      game.tick = 1200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.is_not_nil(history)
      -- ticks = last_seen(1100) - first_seen(1000) = 100, count = 10, avg = 100/10 = 10
      assert.are.equal(100, history.ticks)
      assert.are.equal(10, history.avg)
    end)

    it("does NOT record history in background mode when bot stops delivering", function()
      local nwd = make_networkdata()
      game.tick = 100

      -- Background mode: no history tracking
      process_all(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { target_pos = { x = 1, y = 1 } }) } }),
      })
      game.tick = 200
      process_all(nwd, { make_bot({ unit_number = 1 }) })

      -- Active delivery cleared, but no history recorded
      assert.is_nil(nwd.bot_active_deliveries[1])
      assert.is_nil(nwd.delivery_history["iron-plate:normal"])
    end)
  end)

  -- ─── Edge cases ───────────────────────────────────────────────────

  describe("edge cases", function()
    it("skips bots without unit_number", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ unit_number = nil, orders = { deliver_order("iron-plate", 50) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("iron-plate", 30) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(1, nwd.bot_items["delivering"])
      assert.are.equal(30, nwd.bot_deliveries["iron-plate:normal"].count)
    end)

    it("skips invalid bots", function()
      local nwd = make_networkdata()
      local bots = {
        make_bot({ valid = false, unit_number = 1, orders = { deliver_order("iron-plate", 50) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("copper-plate", 20) } }),
      }

      process_all(nwd, bots)
      assert.are.equal(1, nwd.bot_items["delivering"])
    end)

    it("handles empty bot list", function()
      local nwd = make_networkdata()
      process_all(nwd, {})
      assert.are.equal(0, nwd.bot_items["delivering"])
      assert.are.equal(0, nwd.bot_items["picking"])
    end)
  end)

  -- ─── Last-seen tracking across passes ─────────────────────────────

  describe("last-seen tracking", function()
    it("tracks bots across passes via last_pass_bots_seen", function()
      local nwd = make_networkdata()
      game.tick = 100

      -- Bots must have active deliveries for last-seen transfer to occur
      -- (the transfer is gated on table_size(bot_active_deliveries) > 0)
      -- Pass 1: two delivering bots
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
        make_bot({ unit_number = 2, orders = { deliver_order("copper-plate", 10, { target_pos = { x = 2, y = 2 } }) } }),
      })
      -- After pass 1, last_pass_bots_seen should contain both bots
      assert.is_not_nil(nwd.last_pass_bots_seen[1])
      assert.is_not_nil(nwd.last_pass_bots_seen[2])

      -- Pass 2: only bot 1 remains (still delivering same target)
      game.tick = 200
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
      })
      -- Bot 1 still tracked, bot 2 should be gone
      assert.is_not_nil(nwd.last_pass_bots_seen[1])
      assert.is_nil(nwd.last_pass_bots_seen[2])
    end)

    it("completes delivery for bots that disappear between passes", function()
      local nwd = make_networkdata()

      -- Pass 1: bot delivering (foreground for history)
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { target_pos = { x = 5, y = 5 } }) } }),
      })
      assert.is_not_nil(nwd.bot_active_deliveries[1])

      -- Pass 2: bot gone entirely (destroyed or parked)
      game.tick = 200
      process_all_foreground(nwd, {})

      -- The disappeared bot's delivery should be recorded in history
      local history = nwd.delivery_history["iron-plate:normal"]
      assert.is_not_nil(history)
      assert.are.equal(50, history.count)
      -- Active delivery should be cleared
      assert.is_nil(nwd.bot_active_deliveries[1])
    end)
  end)

  -- ─── Public API ───────────────────────────────────────────────────

  describe("is_scanning_done()", function()
    it("returns true for nil networkdata", function()
      assert.is_true(bot_counter.is_scanning_done(nil))
    end)

    it("returns true when bot_chunker is nil", function()
      assert.is_true(bot_counter.is_scanning_done({ bot_chunker = nil }))
    end)

    it("returns true when chunker is idle", function()
      local nwd = make_networkdata()
      assert.is_true(bot_counter.is_scanning_done(nwd))
    end)

    it("returns false during processing", function()
      local nwd = make_networkdata()
      local network = make_network({ make_bot({ unit_number = 1 }) })
      bot_counter.init_background_processing(nwd, network)
      assert.is_false(bot_counter.is_scanning_done(nwd))
    end)
  end)

  describe("restart_counting()", function()
    it("completes current pass and re-initialises", function()
      local nwd = make_networkdata()
      game.tick = 100

      -- Start processing
      local bots = { make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { target_pos = { x = 1, y = 1 } }) } }) }
      local network = make_network(bots)
      bot_counter.init_background_processing(nwd, network)

      -- Resolve fetcher
      bot_counter.process_next_chunk(nwd)

      -- Restart before finishing
      bot_counter.restart_counting(nwd)

      -- Should be in finalising state after reset
      assert.are.equal("finalising", nwd.bot_chunker.state)
    end)
  end)
end)
