local mock = require("tests.mocks.factorio")

describe("undersupply", function()
  local undersupply

  before_each(function()
    mock.fresh()
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
    }
    undersupply = require("scripts.undersupply")
  end)

  local next_unit_number = 0

  --- Build a mock requester entity with logistic point sections
  local function make_requester(opts)
    opts = opts or {}
    next_unit_number = next_unit_number + 1
    local sections = opts.sections or {}
    local inventory_contents = opts.inventory or {}

    local mock_inventory = {
      get_contents = function()
        return inventory_contents
      end,
    }

    local mock_sections = {}
    for i, section in ipairs(sections) do
      mock_sections[i] = {
        active = section.active ~= false,
        multiplier = section.multiplier or 1,
        filters = section.filters or {},
        filters_count = #(section.filters or {}),
      }
    end

    -- NOTE: Production code uses dot-syntax (entity.get_logistic_point(arg)),
    -- not colon-syntax, so these functions receive args directly — no self.
    local mock_logistic_point = {
      sections_count = #mock_sections,
      get_section = function(idx)
        return mock_sections[idx]
      end,
    }

    return {
      valid = opts.valid ~= false,
      type = opts.type or "logistic-container",
      name = opts.name or "requester-chest",
      status = opts.status or "working",
      unit_number = opts.unit_number or next_unit_number,
      get_logistic_point = function(member_index)
        return mock_logistic_point
      end,
      get_inventory = function(inv_type)
        return mock_inventory
      end,
    }
  end

  describe("initialise_undersupply()", function()
    it("sets up accumulator with empty demand table", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })
      assert.are.same({}, acc.demand)
      assert.are.same({}, acc.net_demand)
      assert.is_false(acc.ignore_player_demands)
    end)

    it("captures context settings", function()
      local acc = {}
      local ignored = { ["iron-plate:normal"] = true }
      undersupply.initialise_undersupply(acc, {
        deliveries = { some = "data" },
        ignored_items = ignored,
        ignore_player_demands = true,
        ignore_buffer_chests_for_undersupply = true,
        requester_cache = {},
      })
      assert.is_true(acc.ignore_player_demands)
      assert.is_true(acc.ignore_buffer_chests_for_undersupply)
      assert.are.equal(ignored, acc.ignored_items_for_undersupply)
    end)
  end)

  describe("process_one_requester()", function()
    it("accumulates demand for requested items", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          filters = {{
            value = { type = "item", name = "iron-plate", quality = "normal" },
            min = 100,
          }},
        }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 30 }},
      })

      local cost = undersupply.process_one_requester(requester, acc)
      assert.are.equal(1, cost)
      -- Demand = 100 requested - 30 in inventory = 70
      assert.are.equal(70, acc.demand["iron-plate:normal"])
    end)

    it("ignores character entities when ignore_player_demands is true", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = true,
        requester_cache = {},
      })

      local requester = make_requester({
        type = "character",
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }},
        }},
      })

      local cost = undersupply.process_one_requester(requester, acc)
      assert.are.equal(0, cost)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)

    it("ignores buffer chests when setting is enabled", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        ignore_buffer_chests_for_undersupply = true,
        requester_cache = {},
      })

      local requester = make_requester({
        type = "logistic-container",
        name = "buffer-chest",
        sections = {{
          filters = {{ value = { type = "item", name = "copper-plate", quality = "normal" }, min = 200 }},
        }},
      })

      local cost = undersupply.process_one_requester(requester, acc)
      assert.are.equal(0, cost)
    end)

    it("ignores entities disabled by circuit network", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        status = defines.entity_status.disabled_by_control_behavior,
        sections = {{
          filters = {{ value = { type = "item", name = "steel-plate", quality = "normal" }, min = 50 }},
        }},
      })

      local cost = undersupply.process_one_requester(requester, acc)
      assert.are.equal(0, cost)
    end)

    it("skips items on the ignore list", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = { ["iron-plate:normal"] = true },
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }},
        }},
        inventory = {},
      })

      undersupply.process_one_requester(requester, acc)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)

    it("skips non-item filter types", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          filters = {
            { value = { type = "fluid", name = "water", quality = "normal" }, min = 500 },
            { value = { type = "item", name = "iron-plate", quality = "normal" }, min = 10 },
          },
        }},
        inventory = {},
      })

      undersupply.process_one_requester(requester, acc)
      assert.is_nil(acc.demand["water:normal"])
      assert.are.equal(10, acc.demand["iron-plate:normal"])
    end)

    it("handles section multiplier", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          multiplier = 3,
          filters = {{ value = { type = "item", name = "copper-wire", quality = "normal" }, min = 10 }},
        }},
        inventory = {},
      })

      undersupply.process_one_requester(requester, acc)
      -- 10 * 3 = 30 requested, 0 in inventory
      assert.are.equal(30, acc.demand["copper-wire:normal"])
    end)

    it("skips inactive sections", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          active = false,
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }},
        }},
        inventory = {},
      })

      undersupply.process_one_requester(requester, acc)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)

    it("does not accumulate demand when inventory satisfies request", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local requester = make_requester({
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }},
        }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 100 }},
      })

      undersupply.process_one_requester(requester, acc)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)

    it("accumulates demand from multiple requesters", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })

      local r1 = make_requester({
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }},
        }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 20 }},
      })
      local r2 = make_requester({
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }},
        }},
        inventory = {},
      })

      undersupply.process_one_requester(r1, acc)
      undersupply.process_one_requester(r2, acc)
      -- (100-20) + 50 = 130
      assert.are.equal(130, acc.demand["iron-plate:normal"])
    end)

    it("returns 1 for invalid entities", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
      })
      -- Invalid entity — the function checks .valid first and the code
      -- returns 1 at end of the outer block. But actually for invalid
      -- entities, the if block is skipped entirely, returning the default
      -- from the function. Let's check what actually happens.
      local requester = { valid = false }
      local cost = undersupply.process_one_requester(requester, acc)
      assert.are.equal(1, cost)
    end)
  end)

  -- Tests for the rolling 1/N sampling scheme. These supply unit_number on
  -- the mock requester so the cache lookup actually runs (most other tests
  -- in this file omit it and exit early — pre-existing limitation).
  describe("rolling 1/N sampling", function()
    --- Build a requester with a unit_number so the cache + slice path runs
    local function make_id_requester(unit_number, opts)
      local r = make_requester(opts)
      r.unit_number = unit_number
      return r
    end

    it("N=1 always samples fresh and never reads from cached_demand", function()
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = {},
        rolling_divisor = 1,
        slice_id = 0,
      })
      local r = make_id_requester(42, {
        sections = {{ filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }} }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 30 }},
      })
      undersupply.process_one_requester(r, acc)
      assert.are.equal(70, acc.demand["iron-plate:normal"])
      -- Second call: change the inventory mock to a fully-satisfied state.
      -- N=1 means we always sample fresh, so demand should reflect the new reality.
      r.get_inventory = function()
        return { get_contents = function() return {{ name = "iron-plate", quality = "normal", count = 100 }} end }
      end
      acc.demand = {}
      undersupply.process_one_requester(r, acc)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)

    it("N>1 caches demand on first visit and reuses it on out-of-slice visits", function()
      local cache = {}
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = cache,
        rolling_divisor = 3,
        slice_id = 0,
      })
      -- First visit: cached_demand is nil, so the requester is in-slice
      -- regardless of its hashed slice. It should sample fresh.
      local r = make_id_requester(42, {
        sections = {{ filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }} }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 30 }},
      })
      undersupply.process_one_requester(r, acc)
      assert.are.equal(70, acc.demand["iron-plate:normal"])
      assert.is_not_nil(cache[42].cached_demand)
      assert.are.equal(70, cache[42].cached_demand["iron-plate:normal"])

      -- Second visit on a sweep where this requester is OUT of slice:
      -- the inventory should NOT be re-read. We change the inventory to a
      -- satisfied state, and rotate slice_id away from the requester's hash slice.
      r.get_inventory = function()
        return { get_contents = function() return {{ name = "iron-plate", quality = "normal", count = 100 }} end }
      end
      local hash_slice = (42 * 2654435761) % 3
      acc.slice_id = (hash_slice + 1) % 3 -- guaranteed out-of-slice
      acc.demand = {}
      undersupply.process_one_requester(r, acc)
      -- The cached value (70) should still be folded in, even though
      -- inventory is now fully satisfied.
      assert.are.equal(70, acc.demand["iron-plate:normal"])
    end)

    it("N>1 re-samples when slice_id matches the requester's hash slice", function()
      local cache = {}
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = cache,
        rolling_divisor = 3,
        slice_id = 0,
      })
      local r = make_id_requester(42, {
        sections = {{ filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }} }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 30 }},
      })
      -- Prime the cache.
      undersupply.process_one_requester(r, acc)
      assert.are.equal(70, cache[42].cached_demand["iron-plate:normal"])

      -- Now rotate slice_id to match the requester's hash slice and change inventory.
      acc.slice_id = (42 * 2654435761) % 3
      r.get_inventory = function()
        return { get_contents = function() return {{ name = "iron-plate", quality = "normal", count = 100 }} end }
      end
      acc.demand = {}
      undersupply.process_one_requester(r, acc)
      -- Fresh sample says satisfied. cached_demand should now be an EMPTY
      -- table (not nil) — nil would mean "never sampled" and would force the
      -- requester back into the in-slice path on every subsequent sweep,
      -- defeating rolling for satisfied (steady-state) requesters.
      assert.is_nil(acc.demand["iron-plate:normal"])
      assert.is_not_nil(cache[42].cached_demand)
      assert.are.equal(0, table_size(cache[42].cached_demand))
    end)

    it("satisfied requesters use the skip path on subsequent out-of-slice sweeps", function()
      -- This is the regression test for the bug found in the first benchmark
      -- run: a satisfied requester was getting cached_demand = nil, which made
      -- the slice predicate force it through the in-slice (fresh-sample) path
      -- on every sweep, completely defeating the rolling optimisation for the
      -- steady-state population that should benefit most.
      local cache = {}
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = cache,
        rolling_divisor = 3,
        slice_id = 0,
      })
      -- A fully satisfied requester (request 50, has 100).
      local r = make_id_requester(42, {
        sections = {{ filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }} }},
        inventory = {{ name = "iron-plate", quality = "normal", count = 100 }},
      })
      -- First visit: cached_demand is nil → in-slice → sample fresh.
      local read_count = 0
      local original_get_inventory = r.get_inventory
      r.get_inventory = function(...)
        read_count = read_count + 1
        return original_get_inventory(...)
      end
      undersupply.process_one_requester(r, acc)
      assert.are.equal(1, read_count) -- one fresh read on first visit
      assert.is_not_nil(cache[42].cached_demand) -- empty table, not nil
      assert.are.equal(0, table_size(cache[42].cached_demand))

      -- Now rotate to an out-of-slice sweep. The requester should NOT be re-read.
      local hash_slice = (42 * 2654435761) % 3
      acc.slice_id = (hash_slice + 1) % 3
      acc.demand = {}
      undersupply.process_one_requester(r, acc)
      assert.are.equal(1, read_count) -- still 1 — the skip path took over
      assert.is_nil(acc.demand["iron-plate:normal"]) -- empty cached, nothing folded
    end)

    it("circuit-disabled requesters short-circuit before the slice predicate", function()
      local cache = {}
      local acc = {}
      undersupply.initialise_undersupply(acc, {
        deliveries = {},
        ignored_items = {},
        ignore_player_demands = false,
        requester_cache = cache,
        rolling_divisor = 3,
        slice_id = 0,
      })
      local r = make_id_requester(42, {
        status = defines.entity_status.disabled_by_control_behavior,
        sections = {{ filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 }} }},
        inventory = {},
      })
      local cost = undersupply.process_one_requester(r, acc)
      assert.are.equal(0, cost)
      assert.is_nil(acc.demand["iron-plate:normal"])
    end)
  end)

  -- Integration-style tests that build context through global_data,
  -- mirroring how analysis-coordinator.lua sets up undersupply processing.
  describe("with global settings driving context", function()
    local global_data

    before_each(function()
      global_data = require("scripts.global-data")
    end)

    --- Build undersupply context the same way analysis-coordinator does
    local function build_context(networkdata)
      local context = {
        deliveries = networkdata.bot_deliveries or {},
        ignored_items = networkdata.ignored_items_for_undersupply or {},
        ignore_buffer_chests_for_undersupply = networkdata.ignore_buffer_chests_for_undersupply,
        requester_cache = {},
      }
      context.ignore_player_demands = global_data.ignore_player_demands_in_undersupply()
      return context
    end

    local function make_player_requester()
      return make_requester({
        type = "character",
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }},
        }},
        inventory = {},
      })
    end

    local function make_chest_requester()
      return make_requester({
        sections = {{
          filters = {{ value = { type = "item", name = "iron-plate", quality = "normal" }, min = 50 }},
        }},
        inventory = {},
      })
    end

    describe("li-ignore-player-demands-in-undersupply = true", function()
      before_each(function()
        settings.global["li-ignore-player-demands-in-undersupply"] = { value = true }
        global_data.settings_changed()
      end)

      it("ignores character (player) demand", function()
        local acc = {}
        undersupply.initialise_undersupply(acc, build_context({}))
        undersupply.process_one_requester(make_player_requester(), acc)
        assert.is_nil(acc.demand["iron-plate:normal"])
      end)

      it("still counts chest demand", function()
        local acc = {}
        undersupply.initialise_undersupply(acc, build_context({}))
        undersupply.process_one_requester(make_chest_requester(), acc)
        assert.are.equal(50, acc.demand["iron-plate:normal"])
      end)

      it("counts only chest demand when both player and chest request the same item", function()
        local acc = {}
        undersupply.initialise_undersupply(acc, build_context({}))
        undersupply.process_one_requester(make_player_requester(), acc)
        undersupply.process_one_requester(make_chest_requester(), acc)
        assert.are.equal(50, acc.demand["iron-plate:normal"])
      end)
    end)

    describe("ignore_buffer_chests_for_undersupply (per-network)", function()
      before_each(function()
        settings.global["li-ignore-player-demands-in-undersupply"] = { value = false }
        global_data.settings_changed()
      end)

      local function make_buffer_requester()
        return make_requester({
          type = "logistic-container",
          name = "buffer-chest",
          sections = {{
            filters = {{ value = { type = "item", name = "copper-plate", quality = "normal" }, min = 80 }},
          }},
          inventory = {},
        })
      end

      it("ignores buffer chest demand when enabled", function()
        local acc = {}
        local nwd = { ignore_buffer_chests_for_undersupply = true }
        undersupply.initialise_undersupply(acc, build_context(nwd))
        undersupply.process_one_requester(make_buffer_requester(), acc)
        assert.is_nil(acc.demand["copper-plate:normal"])
      end)

      it("still counts requester chest demand when buffer chests ignored", function()
        local acc = {}
        local nwd = { ignore_buffer_chests_for_undersupply = true }
        undersupply.initialise_undersupply(acc, build_context(nwd))
        undersupply.process_one_requester(make_chest_requester(), acc)
        assert.are.equal(50, acc.demand["iron-plate:normal"])
      end)

      it("counts buffer chest demand when disabled", function()
        local acc = {}
        local nwd = { ignore_buffer_chests_for_undersupply = false }
        undersupply.initialise_undersupply(acc, build_context(nwd))
        undersupply.process_one_requester(make_buffer_requester(), acc)
        assert.are.equal(80, acc.demand["copper-plate:normal"])
      end)

      it("counts both buffer and requester demand when disabled", function()
        local acc = {}
        local nwd = { ignore_buffer_chests_for_undersupply = false }
        undersupply.initialise_undersupply(acc, build_context(nwd))
        undersupply.process_one_requester(make_buffer_requester(), acc)
        undersupply.process_one_requester(make_chest_requester(), acc)
        assert.are.equal(80, acc.demand["copper-plate:normal"])
        assert.are.equal(50, acc.demand["iron-plate:normal"])
      end)
    end)

    describe("ignored_items_for_undersupply (per-network)", function()
      before_each(function()
        settings.global["li-ignore-player-demands-in-undersupply"] = { value = false }
        global_data.settings_changed()
      end)

      it("skips ignored items but counts others", function()
        local acc = {}
        local nwd = { ignored_items_for_undersupply = { ["iron-plate:normal"] = true } }
        undersupply.initialise_undersupply(acc, build_context(nwd))

        local requester = make_requester({
          sections = {{
            filters = {
              { value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 },
              { value = { type = "item", name = "copper-plate", quality = "normal" }, min = 50 },
            },
          }},
          inventory = {},
        })
        undersupply.process_one_requester(requester, acc)
        assert.is_nil(acc.demand["iron-plate:normal"])
        assert.are.equal(50, acc.demand["copper-plate:normal"])
      end)

      it("counts everything when ignore list is empty", function()
        local acc = {}
        local nwd = { ignored_items_for_undersupply = {} }
        undersupply.initialise_undersupply(acc, build_context(nwd))

        local requester = make_requester({
          sections = {{
            filters = {
              { value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 },
              { value = { type = "item", name = "copper-plate", quality = "normal" }, min = 50 },
            },
          }},
          inventory = {},
        })
        undersupply.process_one_requester(requester, acc)
        assert.are.equal(100, acc.demand["iron-plate:normal"])
        assert.are.equal(50, acc.demand["copper-plate:normal"])
      end)

      it("ignores quality-specific entries only", function()
        local acc = {}
        local nwd = { ignored_items_for_undersupply = { ["iron-plate:uncommon"] = true } }
        undersupply.initialise_undersupply(acc, build_context(nwd))

        local requester = make_requester({
          sections = {{
            filters = {
              { value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100 },
              { value = { type = "item", name = "iron-plate", quality = "uncommon" }, min = 30 },
            },
          }},
          inventory = {},
        })
        undersupply.process_one_requester(requester, acc)
        assert.are.equal(100, acc.demand["iron-plate:normal"])
        assert.is_nil(acc.demand["iron-plate:uncommon"])
      end)
    end)

    describe("li-ignore-player-demands-in-undersupply = false", function()
      before_each(function()
        settings.global["li-ignore-player-demands-in-undersupply"] = { value = false }
        global_data.settings_changed()
      end)

      it("includes character (player) demand", function()
        local acc = {}
        undersupply.initialise_undersupply(acc, build_context({}))
        undersupply.process_one_requester(make_player_requester(), acc)
        assert.are.equal(50, acc.demand["iron-plate:normal"])
      end)

      it("includes both player and chest demand", function()
        local acc = {}
        undersupply.initialise_undersupply(acc, build_context({}))
        undersupply.process_one_requester(make_player_requester(), acc)
        undersupply.process_one_requester(make_chest_requester(), acc)
        assert.are.equal(100, acc.demand["iron-plate:normal"])
      end)
    end)
  end)

  -- ─── all_chunks_done() ──────────────────────────────────────────
  -- Tests the net demand calculation: demand vs network supply vs in-transit.

  describe("all_chunks_done()", function()
    --- Create a mock LuaLogisticNetwork with get_contents()
    --- @param supply_items table Array of { name, quality, count }
    local function make_mock_network(supply_items)
      return {
        valid = true,
        get_contents = function()
          return supply_items or {}
        end,
      }
    end

    --- Set up storage.networks with a networkdata that has a cached network
    local function setup_network(id, supply_items)
      local mock_network = make_mock_network(supply_items)
      storage.networks = storage.networks or {}
      storage.networks[id] = {
        id = id,
        _lua_network = mock_network,
      }
    end

    --- Build an accumulator with demand and optional bot_deliveries
    local function make_accumulator(demand, bot_deliveries)
      return {
        demand = demand or {},
        bot_deliveries = bot_deliveries or {},
        net_demand = {},
      }
    end

    --- Find an entry in net_demand by item_name:quality_name
    local function find_demand(net_demand, item_name, quality_name)
      for _, entry in ipairs(net_demand) do
        if entry.item_name == item_name and entry.quality_name == quality_name then
          return entry
        end
      end
      return nil
    end

    it("produces shortage when demand exceeds supply", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 30 },
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 100,
      })

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(1, #acc.net_demand)
      local entry = acc.net_demand[1]
      assert.are.equal("iron-plate", entry.item_name)
      assert.are.equal("normal", entry.quality_name)
      assert.are.equal(70, entry.shortage)  -- 100 - 30
      assert.are.equal(100, entry.request)
      assert.are.equal(30, entry.supply)
      assert.are.equal(0, entry.under_way)
    end)

    it("produces no entry when supply meets demand", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 100 },
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 50,
      })

      undersupply.all_chunks_done(acc, {}, 1)
      assert.are.equal(0, #acc.net_demand)
    end)

    it("produces no entry when supply exceeds demand", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 200 },
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 50,
      })

      undersupply.all_chunks_done(acc, {}, 1)
      assert.are.equal(0, #acc.net_demand)
    end)

    it("reduces shortage by in-transit deliveries", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 30 },
      })
      local acc = make_accumulator(
        { ["iron-plate:normal"] = 100 },
        { ["iron-plate:normal"] = { count = 20 } }  -- 20 in transit
      )

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(1, #acc.net_demand)
      local entry = acc.net_demand[1]
      assert.are.equal(50, entry.shortage)  -- 100 - 30 - 20
      assert.are.equal(20, entry.under_way)
    end)

    it("eliminates entry when in-transit covers the shortage", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 30 },
      })
      local acc = make_accumulator(
        { ["iron-plate:normal"] = 100 },
        { ["iron-plate:normal"] = { count = 80 } }  -- covers the 70 gap
      )

      undersupply.all_chunks_done(acc, {}, 1)
      assert.are.equal(0, #acc.net_demand)
    end)

    it("handles multiple items with mixed shortage and surplus", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 50 },
        { name = "copper-plate", quality = "normal", count = 200 },
        { name = "steel-plate", quality = "normal", count = 10 },
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 100,   -- shortage: 50
        ["copper-plate:normal"] = 100, -- surplus: no entry
        ["steel-plate:normal"] = 40,   -- shortage: 30
      })

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(2, #acc.net_demand)
      local iron = find_demand(acc.net_demand, "iron-plate", "normal")
      local steel = find_demand(acc.net_demand, "steel-plate", "normal")
      assert.is_not_nil(iron)
      assert.is_not_nil(steel)
      assert.are.equal(50, iron.shortage)
      assert.are.equal(30, steel.shortage)
      -- copper should NOT appear
      assert.is_nil(find_demand(acc.net_demand, "copper-plate", "normal"))
    end)

    it("tracks quality-specific supply separately", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 100 },
        { name = "iron-plate", quality = "uncommon", count = 5 },
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 50,     -- surplus
        ["iron-plate:uncommon"] = 20,   -- shortage: 15
      })

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(1, #acc.net_demand)
      local entry = acc.net_demand[1]
      assert.are.equal("uncommon", entry.quality_name)
      assert.are.equal(15, entry.shortage)
    end)

    it("treats missing supply as zero", function()
      setup_network(1, {})  -- no supply at all
      local acc = make_accumulator({
        ["iron-plate:normal"] = 50,
      })

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(1, #acc.net_demand)
      assert.are.equal(50, acc.net_demand[1].shortage)
    end)

    it("handles empty demand (no requesters)", function()
      setup_network(1, {
        { name = "iron-plate", quality = "normal", count = 100 },
      })
      local acc = make_accumulator({})

      undersupply.all_chunks_done(acc, {}, 1)
      assert.are.equal(0, #acc.net_demand)
    end)

    it("does not crash when networkdata is nil", function()
      storage.networks = {}  -- no network for id 1
      local acc = make_accumulator({ ["iron-plate:normal"] = 50 })

      assert.has_no.errors(function()
        undersupply.all_chunks_done(acc, {}, 1)
      end)
    end)

    it("does not crash when network is invalid", function()
      -- get_LuaNetwork falls through to slow path when _lua_network.valid is false,
      -- which calls game.forces[...]. Mock it to return nil (no force found).
      game.forces = {}
      storage.networks = {}
      storage.networks[1] = {
        id = 1,
        force_name = "player",
        surface = "nauvis",
        _lua_network = { valid = false },
      }
      local acc = make_accumulator({ ["iron-plate:normal"] = 50 })

      assert.has_no.errors(function()
        undersupply.all_chunks_done(acc, {}, 1)
      end)
      -- net_demand should be unchanged (empty)
      assert.are.same({}, acc.net_demand)
    end)

    it("defaults quality to normal when supply item has no quality", function()
      setup_network(1, {
        { name = "iron-plate", count = 80 },  -- no quality field
      })
      local acc = make_accumulator({
        ["iron-plate:normal"] = 100,
      })

      undersupply.all_chunks_done(acc, {}, 1)

      assert.are.equal(1, #acc.net_demand)
      assert.are.equal(20, acc.net_demand[1].shortage) -- 100 - 80
    end)
  end)
end)
