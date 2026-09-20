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
      position = opts.position,
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
  local function pickup_order(item_name, opts)
    opts = opts or {}
    return {
      type = defines.robot_order_type.pickup,
      target_item = {
        name = { name = item_name },
        quality = { name = "normal" },
      },
      target_count = 0,
      target = opts.target_pos and { position = opts.target_pos } or nil,
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

    -- History is kept for a while after the last player leaves a network, and background scans are
    -- all that runs then. They must leave that history exactly as the player left it
    it("leaves an existing history untouched in background mode", function()
      local nwd = make_networkdata()
      nwd.delivery_history_gen = 0

      -- One delivery recorded while a player was watching
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 50, { target_pos = { x = 1, y = 1 } }) } }),
      })
      game.tick = 200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      local count, deliveries = history.count, history.deliveries
      local gen = nwd.delivery_history_gen

      -- The player leaves: from here on only background scans run
      nwd.players_set = {}
      game.tick = 300
      process_all(nwd, {
        make_bot({ unit_number = 2, orders = { deliver_order("iron-plate", 70, { target_pos = { x = 3, y = 3 } }) } }),
      })
      game.tick = 400
      process_all(nwd, { make_bot({ unit_number = 2 }) })

      assert.are.same(history, nwd.delivery_history["iron-plate:normal"]) -- Same table, frozen
      assert.are.equal(count, history.count)
      assert.are.equal(deliveries, history.deliveries)
      assert.are.equal(gen, nwd.delivery_history_gen) -- So the UI does not redraw the row
    end)
  end)

  -- ─── Trip distance ────────────────────────────────────────────────

  describe("trip distance", function()
    --- Run one full delivery for a bot: pickup, deliver, then idle
    local function run_trip(nwd, unit_number, item_name, count, pickup_pos, target_pos, start_tick)
      game.tick = start_tick
      process_all_foreground(nwd, {
        make_bot({ unit_number = unit_number, orders = { pickup_order(item_name, { target_pos = pickup_pos }) } }),
      })
      game.tick = start_tick + 10
      process_all_foreground(nwd, {
        make_bot({ unit_number = unit_number, orders = { deliver_order(item_name, count, { target_pos = target_pos }) } }),
      })
      game.tick = start_tick + 20
      process_all_foreground(nwd, { make_bot({ unit_number = unit_number }) })
    end

    it("records pickup-to-target distance for a delivery", function()
      local nwd = make_networkdata()
      run_trip(nwd, 1, "iron-plate", 10, { x = 0, y = 0 }, { x = 30, y = 40 }, 100)

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(1, history.dist_count)
      assert.are.equal(50, history.dist_sum)
      assert.are.equal(50, history.avg_dist)
      assert.are.equal(50, history.max_dist)
    end)

    it("averages distance per delivery, so bulk short trips don't hide long ones", function()
      local nwd = make_networkdata()
      -- Mall: 4 short trips of 200 items, 3 tiles each
      for i = 1, 4 do
        run_trip(nwd, i, "iron-plate", 200, { x = 0, y = 0 }, { x = 3, y = 0 }, 100 * i)
      end
      -- Outpost: 1 long trip of 10 items, 603 tiles
      run_trip(nwd, 9, "iron-plate", 10, { x = 0, y = 0 }, { x = 603, y = 0 }, 1000)

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(810, history.count)
      assert.are.equal(5, history.deliveries)
      assert.are.equal(5, history.dist_count)
      assert.are.equal(5, history.dist_exact)
      assert.are.equal((4 * 3 + 603) / 5, history.avg_dist) -- 123, not dragged towards 3 by item count
      assert.are.equal(4 * 3 + 603, history.dist_sum) -- Distance carried
      -- The median is the typical trip, which the one long trip doesn't pull up
      assert.are.equal(3, math.floor(require("scripts.network-data").median_trip(history) + 0.5))
      assert.are.equal(603, history.max_dist)
      -- Both ends of the longest trips are kept so they can be shown on the map. The four mall
      -- trips all went to the same chest, so only one of them is kept
      -- The mall chest's deliveries are counted, and when it was last delivered to is kept
      assert.are.same({
        { dist = 603, from_x = 0, from_y = 0, to_x = 603, to_y = 0, exact = true, deliveries = 1, last_tick = 1010 },
        { dist = 3, from_x = 0, from_y = 0, to_x = 3, to_y = 0, exact = true, deliveries = 4, last_tick = 410 },
      }, history.top_trips)
    end)

    it("estimates the median trip to within a few percent", function()
      local nwd = make_networkdata()
      -- 11 trips of 100, 200 ... 1100 tiles: the median is 600
      for i = 1, 11 do
        run_trip(nwd, i, "iron-plate", 1, { x = 0, y = 0 }, { x = i * 100, y = 0 }, 100 * i)
      end
      local median = require("scripts.network-data").median_trip(nwd.delivery_history["iron-plate:normal"])
      assert.is_true(math.abs(median - 600) / 600 < 0.1, "median estimate " .. median)
    end)

    it("counts repeat trips to a destination, even when it's the shortest one listed", function()
      local nwd = make_networkdata()
      for i = 1, 5 do -- Fill the list: 100 ... 500 tiles
        run_trip(nwd, i, "iron-plate", 1, { x = 0, y = 0 }, { x = i * 100, y = 0 }, 100 * i)
      end
      run_trip(nwd, 6, "iron-plate", 1, { x = 0, y = 0 }, { x = 100, y = 0 }, 1000) -- Repeat of the shortest

      local trips = nwd.delivery_history["iron-plate:normal"].top_trips
      assert.are.same({ 100, 2, 1010 }, { trips[5].dist, trips[5].deliveries, trips[5].last_tick })
    end)

    it("moves a destination up the list when a longer trip goes there", function()
      local nwd = make_networkdata()
      run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 300, y = 0 }, 100)   -- 300
      run_trip(nwd, 2, "iron-plate", 1, { x = 200, y = 0 }, { x = 400, y = 0 }, 200) -- 200
      run_trip(nwd, 3, "iron-plate", 1, { x = 0, y = 0 }, { x = 400, y = 0 }, 300)   -- 400: same chest, longer

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.same({ 400, 2 }, { history.top_trips[1].dist, history.top_trips[1].deliveries })
      assert.are.equal(300, history.top_trips[2].dist)
      assert.are.equal(400, history.top_dist)
    end)

    it("keeps the five longest trips, longest first", function()
      local nwd = make_networkdata()
      for i = 1, 7 do
        -- Trips of 10, 20 ... 70 tiles, each to a different chest, in a mixed-up order
        local dist = ((i * 3) % 7 + 1) * 10
        run_trip(nwd, i, "iron-plate", 1, { x = 0, y = 0 }, { x = dist, y = 0 }, 100 * i)
      end

      local dists = {}
      for _, trip in ipairs(nwd.delivery_history["iron-plate:normal"].top_trips) do
        dists[#dists + 1] = trip.dist
      end
      assert.are.same({ 70, 60, 50, 40, 30 }, dists)
    end)

    it("keeps only the longest trip to each destination", function()
      local nwd = make_networkdata()
      local chest = { x = 100, y = 0 }
      run_trip(nwd, 1, "iron-plate", 1, { x = 50, y = 0 }, chest, 100)   -- 50 tiles
      run_trip(nwd, 2, "iron-plate", 1, { x = 60, y = 0 }, chest, 200)   -- 40: shorter, ignored
      run_trip(nwd, 3, "iron-plate", 1, { x = 0, y = 0 }, { x = 70, y = 0 }, 300) -- 70, elsewhere
      run_trip(nwd, 4, "iron-plate", 1, { x = 20, y = 0 }, chest, 400)   -- 80: replaces the 50

      local trips = nwd.delivery_history["iron-plate:normal"].top_trips
      assert.are.equal(2, #trips)
      assert.are.same({ 80, 20 }, { trips[1].dist, trips[1].from_x })
      assert.are.same({ 70, 70 }, { trips[2].dist, trips[2].to_x })
    end)

    describe("ignored trips", function()
      local network_data
      before_each(function()
        network_data = require("scripts.network-data")
      end)

      local function dists(nwd)
        local result = {}
        for _, trip in ipairs(nwd.delivery_history["iron-plate:normal"].top_trips) do
          result[#result + 1] = trip.dist
        end
        return result
      end

      it("stops listing an ignored trip straight away, and the next one moves up", function()
        local nwd = make_networkdata()
        run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 600, y = 0 }, 100)
        run_trip(nwd, 2, "iron-plate", 1, { x = 0, y = 0 }, { x = 400, y = 0 }, 200)
        local gen = nwd.delivery_history_gen

        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)

        local history = nwd.delivery_history["iron-plate:normal"]
        assert.are.same({ 400 }, dists(nwd))
        assert.are.equal(400, history.top_dist)
        assert.are.equal(1, history.ignored_count)
        assert.is_true(nwd.delivery_history_gen > gen) -- So the row is redrawn
        -- The statistics still include it
        assert.are.equal(600, history.max_dist)
        assert.are.equal(2, history.dist_count)
      end)

      it("doesn't list new trips to an ignored destination, but counts them", function()
        local nwd = make_networkdata()
        run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 100, y = 0 }, 100)
        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)
        run_trip(nwd, 2, "iron-plate", 1, { x = 0, y = 0 }, { x = 600, y = 0 }, 200)

        local history = nwd.delivery_history["iron-plate:normal"]
        assert.are.same({ 100 }, dists(nwd))
        assert.are.equal(600, history.max_dist)
        assert.are.equal(2, history.dist_count)
      end)

      it("only ignores that item's trips to that destination", function()
        local nwd = make_networkdata()
        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)
        run_trip(nwd, 1, "copper-plate", 1, { x = 0, y = 0 }, { x = 600, y = 0 }, 100)
        run_trip(nwd, 2, "iron-plate", 1, { x = 0, y = 0 }, { x = 600, y = 1 }, 200)

        assert.are.equal(600, nwd.delivery_history["copper-plate:normal"].top_dist)
        assert.are.equal(1, #nwd.delivery_history["iron-plate:normal"].top_trips)
      end)

      it("counts ignores for an item first delivered after they were made", function()
        local nwd = make_networkdata()
        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)
        network_data.ignore_trip(nwd, "iron-plate", "normal", 700, 0)
        network_data.ignore_trip(nwd, "iron-plate", "normal", 700, 0) -- Already ignored
        network_data.ignore_trip(nwd, "copper-plate", "normal", 600, 0)
        run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 100, y = 0 }, 100)

        assert.are.equal(2, nwd.delivery_history["iron-plate:normal"].ignored_count)
        assert.are.equal(3, table_size(nwd.ignored_trips))
      end)

      it("lists trips again from their next delivery once un-ignored", function()
        local nwd = make_networkdata()
        run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 600, y = 0 }, 100)
        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)
        local key = network_data.trip_ignore_key("iron-plate:normal", 600, 0)

        network_data.unignore_trip(nwd, key)
        local history = nwd.delivery_history["iron-plate:normal"]
        assert.are.equal(0, history.ignored_count)
        assert.are.same({}, dists(nwd)) -- Past trips aren't brought back

        run_trip(nwd, 2, "iron-plate", 1, { x = 0, y = 0 }, { x = 600, y = 0 }, 200)
        assert.are.same({ 600 }, dists(nwd))
      end)

      it("clears the whole list", function()
        local nwd = make_networkdata()
        run_trip(nwd, 1, "iron-plate", 1, { x = 0, y = 0 }, { x = 100, y = 0 }, 100)
        network_data.ignore_trip(nwd, "iron-plate", "normal", 600, 0)
        network_data.clear_ignored_trips(nwd)

        assert.are.equal(0, table_size(nwd.ignored_trips))
        assert.are.equal(0, nwd.delivery_history["iron-plate:normal"].ignored_count)
      end)
    end)

    it("estimates the trip from where the bot was first seen when the pickup was missed", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, position = { x = 0, y = 0 },
          orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      game.tick = 200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(1, history.dist_count)
      assert.are.equal(0, history.dist_exact)
      assert.are.equal(50, history.max_dist)
      assert.are.same({ 0, 0, false }, { history.top_trips[1].from_x, history.top_trips[1].from_y, history.top_trips[1].exact })
    end)

    it("marks an estimated start as tracked when the bot was seen in the previous pass", function()
      local nwd = make_networkdata()
      -- Pass 1: the bot is idle, so we look at it and know it is not carrying anything
      game.tick = 100
      process_all_foreground(nwd, { make_bot({ unit_number = 1, position = { x = 0, y = 0 } }) })
      -- Pass 2: it is delivering, with no pickup seen. It can only have flown since pass 1
      game.tick = 200
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, position = { x = 0, y = 0 },
          orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      game.tick = 300
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local trip = nwd.delivery_history["iron-plate:normal"].top_trips[1]
      assert.is_false(trip.exact)
      assert.is_true(trip.tracked)
    end)

    it("leaves an estimated start untracked when the bot is seen for the first time", function()
      local nwd = make_networkdata()
      -- Straight into a delivery: this bot could have been flying for any length of time
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, position = { x = 0, y = 0 },
          orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      game.tick = 200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local trip = nwd.delivery_history["iron-plate:normal"].top_trips[1]
      assert.is_false(trip.exact)
      assert.is_nil(trip.tracked)
    end)

    it("does not mark a measured start as tracked, as there is nothing to estimate", function()
      local nwd = make_networkdata()
      run_trip(nwd, 1, "iron-plate", 10, { x = 0, y = 0 }, { x = 30, y = 40 }, 100)

      local trip = nwd.delivery_history["iron-plate:normal"].top_trips[1]
      assert.is_true(trip.exact)
      assert.is_nil(trip.tracked)
    end)

    it("prefers the pickup chest over the bot's position", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, position = { x = 5, y = 5 },
          orders = { pickup_order("iron-plate", { target_pos = { x = 0, y = 0 } }) } }),
      })
      game.tick = 110
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, position = { x = 20, y = 20 },
          orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      game.tick = 120
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(50, history.max_dist) -- From the chest at 0,0, not the bot at 20,20
      assert.are.equal(1, history.dist_exact)
    end)

    it("does not estimate trips in background mode", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all(nwd, {
        make_bot({ unit_number = 1, position = { x = 0, y = 0 },
          orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      assert.is_nil(nwd.bot_active_deliveries[1].trip_dist)
    end)

    it("does not use a pickup of a different item", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { pickup_order("copper-plate", { target_pos = { x = 0, y = 0 } }) } }),
      })
      game.tick = 110
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 30, y = 40 } }) } }),
      })
      game.tick = 120
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(10, history.count)
      assert.are.equal(0, history.dist_count)
      assert.is_nil(nwd.bot_pickup_positions[1]) -- Consumed even though it didn't match
    end)

    it("still records the delivery when the pickup was not observed", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
      })
      game.tick = 200
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { deliver_order("iron-plate", 10, { target_pos = { x = 1, y = 1 } }) } }),
      })
      game.tick = 300
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })

      local history = nwd.delivery_history["iron-plate:normal"]
      assert.are.equal(10, history.count)
      assert.are.equal(1, history.deliveries) -- Counted, so the tooltip can show distance coverage
      assert.are.equal(0, history.dist_count)
      assert.are.equal(0, history.max_dist)
    end)

    it("ignores pickup orders without a target", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { pickup_order("iron-plate") } }),
      })
      assert.is_nil(nwd.bot_pickup_positions and nwd.bot_pickup_positions[1])
    end)

    it("does not record pickups in background mode", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all(nwd, {
        make_bot({ unit_number = 1, orders = { pickup_order("iron-plate", { target_pos = { x = 0, y = 0 } }) } }),
      })
      assert.is_nil(nwd.bot_pickup_positions and nwd.bot_pickup_positions[1])
    end)

    it("forgets a pickup when the bot is seen idle", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { pickup_order("iron-plate", { target_pos = { x = 0, y = 0 } }) } }),
      })
      assert.is_not_nil(nwd.bot_pickup_positions[1])

      game.tick = 110
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }) })
      assert.is_nil(nwd.bot_pickup_positions[1])
    end)

    it("reuses the pending record when the same pickup is seen again", function()
      local nwd = make_networkdata()
      local pickup = pickup_order("iron-plate", { target_pos = { x = 5, y = 5 } })
      game.tick = 100
      process_all_foreground(nwd, { make_bot({ unit_number = 1, orders = { pickup } }) })
      local first = nwd.bot_pickup_positions[1]

      game.tick = 107
      process_all_foreground(nwd, { make_bot({ unit_number = 1, orders = { pickup } }) })
      assert.are.equal(first, nwd.bot_pickup_positions[1])
      assert.are.equal(107, first.seen)
    end)

    it("prunes pickups not refreshed since the last completed scan", function()
      local nwd = make_networkdata()
      game.tick = 100
      process_all_foreground(nwd, {
        make_bot({ unit_number = 1, orders = { pickup_order("iron-plate", { target_pos = { x = 0, y = 0 } }) } }),
      })
      assert.is_not_nil(nwd.bot_pickup_positions[1])

      -- A later scan completes without seeing this bot picking up
      nwd.last_scanned_tick = 150
      game.tick = 200
      process_all_foreground(nwd, {
        make_bot({ unit_number = 2, orders = { pickup_order("iron-plate", { target_pos = { x = 9, y = 9 } }) } }),
      })
      assert.is_nil(nwd.bot_pickup_positions[1])
      assert.is_not_nil(nwd.bot_pickup_positions[2])
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

    it("carries bots forward even when nothing is being delivered", function()
      local nwd = make_networkdata()
      -- An idle network still has to remember which bots it has looked at, so the next delivery
      -- can tell a bot it has seen before from one it is seeing for the first time
      game.tick = 100
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }), make_bot({ unit_number = 2 }) })
      assert.is_not_nil(nwd.last_pass_bots_seen[1])

      game.tick = 200
      process_all_foreground(nwd, { make_bot({ unit_number = 1 }), make_bot({ unit_number = 2 }) })
      assert.is_not_nil(nwd.last_pass_bots_seen[1])
      assert.is_not_nil(nwd.last_pass_bots_seen[2])
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
