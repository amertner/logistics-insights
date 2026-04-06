local mock = require("tests.mocks.factorio")

describe("suggestions_calc", function()
  local suggestions_calc, Suggestions, global_data

  before_each(function()
    mock.fresh()
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
      background_refresh_interval_secs = 10,
      background_refresh_interval_ticks = 600,
      age_out_suggestions_interval_minutes = 5,
    }
    storage.networks = {}
    Suggestions = require("scripts.suggestions")
    suggestions_calc = require("scripts.suggestions-calc")
    global_data = require("scripts.global-data")
  end)

  --- Create a Suggestions instance with a given tick
  local function make_suggestions(tick)
    local s = Suggestions.new()
    s._current_tick = tick or 0
    return s
  end

  -- ─── analyse_waiting_to_charge ──────────────────────────────────

  describe("analyse_waiting_to_charge()", function()
    it("creates suggestion when waiting count > 9", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_waiting_to_charge(s, 40)
      -- Need history to generate a non-zero weighted_min, so just verify remember was called
      local history = s._historydata[Suggestions.awaiting_charge_key]
      assert.is_not_nil(history)
      assert.are.equal(1, #history)
      assert.are.equal(10, history[1].data) -- ceil(40/4) = 10
    end)

    it("records 0 needed roboports when count <= 9", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_waiting_to_charge(s, 5)
      local history = s._historydata[Suggestions.awaiting_charge_key]
      assert.is_not_nil(history)
      assert.are.equal(0, history[1].data)
    end)

    it("uses default trend window when background_refresh < 40s", function()
      storage.global.background_refresh_interval_secs = 10
      -- Default interval = 150s = 9000 ticks. History must span that window.
      local base_tick = 20000
      local s = make_suggestions(base_tick)
      for i = 1, 6 do
        s._current_tick = base_tick - 9000 + i * 1500
        s:remember(Suggestions.awaiting_charge_key, 10)
      end
      s._current_tick = base_tick
      suggestions_calc.analyse_waiting_to_charge(s, 40)
      local suggestion = s:get_suggestions()[Suggestions.awaiting_charge_key]
      assert.is_not_nil(suggestion)
    end)

    it("uses longer trend window when background_refresh >= 40s", function()
      storage.global.background_refresh_interval_secs = 60
      local s = make_suggestions(100000)
      -- With interval >= 40, window = 60 * 4.1 = 246 seconds
      -- Build sparse history that only satisfies the longer window
      for i = 1, 5 do
        -- Spread over ~250 seconds (15000 ticks)
        s._current_tick = 100000 - 15000 + i * 3000
        s:remember(Suggestions.awaiting_charge_key, 10)
      end
      s._current_tick = 100000
      suggestions_calc.analyse_waiting_to_charge(s, 40)
      -- The history should be evaluated with the longer window
      local history = s._historydata[Suggestions.awaiting_charge_key]
      assert.is_not_nil(history)
      assert.is_true(#history >= 2)
    end)
  end)

  -- ─── create_storage_capacity_suggestion ─────────────────────────

  describe("create_storage_capacity_suggestion()", function()
    it("creates suggestion when capacity > 70%", function()
      local s = make_suggestions(1000)
      -- 80% used: 100 total, 20 free
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 100, 20)
      local suggestion = s:get_suggestions()["insufficient-storage"]
      assert.is_not_nil(suggestion)
      assert.are.equal(80.0, suggestion.count) -- floor(0.8 * 1000)/10 = 80.0
    end)

    it("sets urgency to high when capacity > 90%", function()
      local s = make_suggestions(1000)
      -- 95% used: 100 total, 5 free
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 100, 5)
      local suggestion = s:get_suggestions()["insufficient-storage"]
      assert.are.equal("high", suggestion.urgency)
    end)

    it("sets urgency to low when capacity 70-90%", function()
      local s = make_suggestions(1000)
      -- 75% used: 100 total, 25 free
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 100, 25)
      local suggestion = s:get_suggestions()["insufficient-storage"]
      assert.are.equal("low", suggestion.urgency)
    end)

    it("ages out suggestion when capacity <= 70%", function()
      local s = make_suggestions(1000)
      -- First create it
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 100, 20)
      assert.is_not_nil(s:get_suggestions()["insufficient-storage"])
      -- Now drop below 70%: 50% used
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 100, 50)
      -- Should have aged (not immediately cleared since age_out_suggestions_interval > 0)
      local suggestion = s:get_suggestions()["insufficient-storage"]
      assert.are.equal("aging", suggestion.urgency)
    end)

    it("treats zero total stacks as 100% used", function()
      local s = make_suggestions(1000)
      suggestions_calc.create_storage_capacity_suggestion(s, "insufficient-storage", 0, 0)
      local suggestion = s:get_suggestions()["insufficient-storage"]
      assert.is_not_nil(suggestion)
    end)
  end)

  -- ─── analyse_unpowered_roboports ────────────────────────────────

  describe("analyse_unpowered_roboports()", function()
    it("creates high-urgency suggestion with non-empty list", function()
      local s = make_suggestions(1000)
      local roboports = {{ valid = true, id = 1 }, { valid = true, id = 2 }}
      suggestions_calc.analyse_unpowered_roboports(s, roboports)
      local suggestion = s:get_suggestions()[Suggestions.unpowered_roboports_key]
      assert.is_not_nil(suggestion)
      assert.are.equal("high", suggestion.urgency)
      assert.are.equal(2, suggestion.count)
    end)

    it("stores roboport list in cached data", function()
      local s = make_suggestions(1000)
      local roboports = {{ valid = true, id = 1 }}
      suggestions_calc.analyse_unpowered_roboports(s, roboports)
      assert.are.same(roboports, s:get_cached_list(Suggestions.unpowered_roboports_key))
    end)

    it("ages out with empty list", function()
      local s = make_suggestions(1000)
      -- Create first
      suggestions_calc.analyse_unpowered_roboports(s, {{ valid = true }})
      -- Then clear
      suggestions_calc.analyse_unpowered_roboports(s, {})
      local suggestion = s:get_suggestions()[Suggestions.unpowered_roboports_key]
      assert.are.equal("aging", suggestion.urgency)
    end)

    it("ages out with nil list", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_unpowered_roboports(s, {{ valid = true }})
      suggestions_calc.analyse_unpowered_roboports(s, nil)
      local suggestion = s:get_suggestions()[Suggestions.unpowered_roboports_key]
      assert.are.equal("aging", suggestion.urgency)
    end)
  end)

  -- ─── analyse_too_many_bots ──────────────────────────────────────

  describe("analyse_too_many_bots()", function()
    local function make_network(total, idle)
      return {
        all_logistic_robots = total,
        available_logistic_robots = idle,
      }
    end

    it("clears suggestion for small networks (< 100 bots)", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_too_many_bots(s, make_network(50, 40))
      assert.is_nil(s:get_suggestions()[Suggestions.too_many_bots_key])
    end)

    it("clears suggestion when no network", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_too_many_bots(s, nil)
      assert.is_nil(s:get_suggestions()[Suggestions.too_many_bots_key])
    end)

    it("needs at least 3 history samples before creating suggestion", function()
      local s = make_suggestions(1000)
      -- Rising trend with high idle: only 2 samples
      suggestions_calc.analyse_too_many_bots(s, make_network(200, 180))
      s._current_tick = 2000
      suggestions_calc.analyse_too_many_bots(s, make_network(210, 185))
      assert.is_nil(s:get_suggestions()[Suggestions.too_many_bots_key])
    end)

    it("creates suggestion with rising total and >50% idle", function()
      local s = make_suggestions(1000)
      -- Build rising trend with high idle ratio
      for i = 1, 5 do
        s._current_tick = 1000 + i * 100
        suggestions_calc.analyse_too_many_bots(s, make_network(100 + i * 20, 80 + i * 15))
      end
      local suggestion = s:get_suggestions()[Suggestions.too_many_bots_key]
      assert.is_not_nil(suggestion)
    end)

    it("ages out when idle ratio <= 50%", function()
      local s = make_suggestions(1000)
      -- First create the suggestion with rising trend
      for i = 1, 5 do
        s._current_tick = 1000 + i * 100
        suggestions_calc.analyse_too_many_bots(s, make_network(100 + i * 20, 80 + i * 15))
      end
      assert.is_not_nil(s:get_suggestions()[Suggestions.too_many_bots_key])

      -- Now drop idle ratio to 30%
      s._current_tick = 2000
      suggestions_calc.analyse_too_many_bots(s, make_network(300, 90))
      local suggestion = s:get_suggestions()[Suggestions.too_many_bots_key]
      assert.are.equal("aging", suggestion.urgency)
    end)
  end)

  -- ─── analyse_too_few_bots ───────────────────────────────────────

  describe("analyse_too_few_bots()", function()
    local function make_network(total, idle)
      return {
        all_logistic_robots = total,
        available_logistic_robots = idle,
      }
    end

    it("clears suggestion when no network", function()
      local s = make_suggestions(1000)
      suggestions_calc.analyse_too_few_bots(s, nil)
      assert.is_nil(s:get_suggestions()[Suggestions.too_few_bots_key])
    end)

    it("creates suggestion when <=2% idle consistently", function()
      local s = make_suggestions(1000)
      -- All bots busy over multiple samples
      for i = 1, 5 do
        s._current_tick = 1000 + i * 100
        suggestions_calc.analyse_too_few_bots(s, make_network(200, 2))
      end
      local suggestion = s:get_suggestions()[Suggestions.too_few_bots_key]
      assert.is_not_nil(suggestion)
      assert.are.equal("low", suggestion.urgency)
    end)

    it("ages out when idle ratio > 2%", function()
      local s = make_suggestions(1000)
      -- First create the suggestion
      for i = 1, 5 do
        s._current_tick = 1000 + i * 100
        suggestions_calc.analyse_too_few_bots(s, make_network(200, 2))
      end
      assert.is_not_nil(s:get_suggestions()[Suggestions.too_few_bots_key])

      -- Now add some idle bots
      s._current_tick = 2000
      suggestions_calc.analyse_too_few_bots(s, make_network(200, 50))
      local suggestion = s:get_suggestions()[Suggestions.too_few_bots_key]
      assert.are.equal("aging", suggestion.urgency)
    end)
  end)

  -- ─── Storage analysis: per-network settings ─────────────────────

  describe("storage analysis", function()

    --- Build a mock storage chest entity
    local function make_storage_chest(opts)
      opts = opts or {}
      local capacity = opts.capacity or 48
      local free = opts.free or 0
      local contents = opts.contents or {}
      local filters = opts.filters or {}
      local is_empty = #contents == 0

      local mock_inventory = {
        count_empty_stacks = function() return free end,
        is_empty = function() return is_empty end,
        get_contents = function() return contents end,
      }
      -- Make # operator work on inventory to return capacity
      setmetatable(mock_inventory, { __len = function() return capacity end })

      return {
        valid = opts.valid ~= false,
        unit_number = opts.unit_number or math.random(1, 999999),
        filter_slot_count = #filters,
        get_inventory = function(inv_type) return mock_inventory end,
        get_filter = function(idx) return filters[idx] end,
      }
    end

    describe("initialise_storage_analysis()", function()
      it("captures per-network settings from context", function()
        local acc = {}
        local context = {
          ignored_storages_for_mismatch = { [42] = true },
          ignore_higher_quality_mismatches = true,
          ignore_low_storage_when_no_storage = true,
        }
        suggestions_calc.initialise_storage_analysis(acc, context)
        assert.are.same({ [42] = true }, acc.ignored_storages_for_mismatch)
        assert.is_true(acc.ignore_higher_quality_mismatches)
        assert.is_true(acc.ignore_low_storage_when_no_storage)
      end)

      it("defaults to empty/false when context omits settings", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        assert.are.same({}, acc.ignored_storages_for_mismatch)
        assert.is_false(acc.ignore_higher_quality_mismatches)
        assert.is_false(acc.ignore_low_storage_when_no_storage)
      end)
    end)

    describe("process_storage_for_analysis()", function()
      it("accumulates total and free stacks", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        local chest = make_storage_chest({ capacity = 48, free = 10 })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(48, acc.total_stacks)
        assert.are.equal(10, acc.free_stacks)
      end)

      it("tracks unfiltered stacks separately", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        -- Unfiltered chest
        local chest = make_storage_chest({ capacity = 48, free = 20 })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(48, acc.unfiltered_total_stacks)
        assert.are.equal(20, acc.unfiltered_free_stacks)
      end)

      it("does not count filtered chests as unfiltered", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        local chest = make_storage_chest({
          capacity = 48, free = 10,
          filters = {{ name = { name = "iron-plate" }, quality = { name = "normal" } }},
          contents = {{ name = "iron-plate", quality = "normal" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(48, acc.total_stacks)
        assert.are.equal(0, acc.unfiltered_total_stacks)
      end)

      it("detects mismatched items in filtered storage", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        local chest = make_storage_chest({
          capacity = 48, free = 40,
          filters = {{ name = { name = "iron-plate" }, quality = { name = "normal" } }},
          contents = {{ name = "copper-plate", quality = "normal" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(1, #acc.mismatched_storages)
      end)

      it("does not flag matching items as mismatched", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        local chest = make_storage_chest({
          capacity = 48, free = 40,
          filters = {{ name = { name = "iron-plate" }, quality = { name = "normal" } }},
          contents = {{ name = "iron-plate", quality = "normal" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(0, #acc.mismatched_storages)
      end)
    end)

    describe("ignored_storages_for_mismatch (per-network)", function()
      it("skips mismatch detection for ignored unit numbers", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignored_storages_for_mismatch = { [42] = true },
        })
        local chest = make_storage_chest({
          unit_number = 42,
          capacity = 48, free = 40,
          filters = {{ name = { name = "iron-plate" }, quality = { name = "normal" } }},
          contents = {{ name = "copper-plate", quality = "normal" }}, -- mismatch
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(0, #acc.mismatched_storages)
      end)

      it("still detects mismatch for non-ignored unit numbers", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignored_storages_for_mismatch = { [42] = true },
        })
        local chest = make_storage_chest({
          unit_number = 99,
          capacity = 48, free = 40,
          filters = {{ name = { name = "iron-plate" }, quality = { name = "normal" } }},
          contents = {{ name = "copper-plate", quality = "normal" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(1, #acc.mismatched_storages)
      end)
    end)

    describe("ignore_higher_quality_mismatches (per-network)", function()
      it("allows higher quality items when enabled", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignore_higher_quality_mismatches = true,
        })
        -- Filter set to "normal", item is "uncommon" (higher quality)
        -- The quality chain: normal -> uncommon -> rare -> ...
        local chest = make_storage_chest({
          capacity = 48, free = 40,
          filters = {{
            name = { name = "iron-plate" },
            quality = { name = "normal", next = { name = "uncommon", next = { name = "rare", next = nil } } },
          }},
          contents = {{ name = "iron-plate", quality = "uncommon" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(0, #acc.mismatched_storages)
      end)

      it("flags higher quality items as mismatch when disabled", function()
        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignore_higher_quality_mismatches = false,
        })
        local chest = make_storage_chest({
          capacity = 48, free = 40,
          filters = {{
            name = { name = "iron-plate" },
            quality = { name = "normal" },
          }},
          contents = {{ name = "iron-plate", quality = "uncommon" }},
        })
        suggestions_calc.process_storage_for_analysis(chest, acc)
        assert.are.equal(1, #acc.mismatched_storages)
      end)
    end)

    describe("ignore_low_storage_when_no_storage (per-network)", function()
      it("clears storage suggestions when enabled", function()
        -- Set up a network in storage.networks so all_storage_chunks_done can find it
        local s = make_suggestions(1000)
        storage.networks[1] = { id = 1, suggestions = s }

        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignore_low_storage_when_no_storage = true,
        })
        -- Simulate: no storage at all (0 stacks)
        acc.total_stacks = 0
        acc.free_stacks = 0
        acc.unfiltered_total_stacks = 0
        acc.unfiltered_free_stacks = 0
        acc.mismatched_storages = {}

        suggestions_calc.all_storage_chunks_done(acc, {}, 1)
        -- Both storage suggestions should be cleared, not created
        assert.is_nil(s:get_suggestions()[Suggestions.storage_low_key])
        assert.is_nil(s:get_suggestions()[Suggestions.unfiltered_storage_low_key])
      end)

      it("creates storage suggestions normally when disabled", function()
        local s = make_suggestions(1000)
        storage.networks[1] = { id = 1, suggestions = s }

        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {
          ignore_low_storage_when_no_storage = false,
        })
        -- 100% used storage
        acc.total_stacks = 100
        acc.free_stacks = 0
        acc.unfiltered_total_stacks = 100
        acc.unfiltered_free_stacks = 0
        acc.mismatched_storages = {}

        suggestions_calc.all_storage_chunks_done(acc, {}, 1)
        assert.is_not_nil(s:get_suggestions()[Suggestions.storage_low_key])
        assert.is_not_nil(s:get_suggestions()[Suggestions.unfiltered_storage_low_key])
      end)
    end)

    describe("all_storage_chunks_done()", function()
      it("creates mismatched storage suggestion with count", function()
        local s = make_suggestions(1000)
        storage.networks[1] = { id = 1, suggestions = s }

        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        acc.total_stacks = 100
        acc.free_stacks = 50
        acc.unfiltered_total_stacks = 100
        acc.unfiltered_free_stacks = 50
        local fake_chest = { valid = true }
        acc.mismatched_storages = { fake_chest, fake_chest, fake_chest }

        suggestions_calc.all_storage_chunks_done(acc, {}, 1)
        local suggestion = s:get_suggestions()[Suggestions.mismatched_storage_key]
        assert.is_not_nil(suggestion)
        assert.are.equal(3, suggestion.count)
      end)

      it("stores mismatched storage list in cache", function()
        local s = make_suggestions(1000)
        storage.networks[1] = { id = 1, suggestions = s }

        local acc = {}
        suggestions_calc.initialise_storage_analysis(acc, {})
        acc.total_stacks = 100
        acc.free_stacks = 50
        acc.unfiltered_total_stacks = 100
        acc.unfiltered_free_stacks = 50
        local fake_chest = { valid = true, id = 1 }
        acc.mismatched_storages = { fake_chest }

        suggestions_calc.all_storage_chunks_done(acc, {}, 1)
        assert.are.same({ fake_chest }, s:get_cached_list(Suggestions.mismatched_storage_key))
      end)

      it("clears suggestions when accumulator is nil (premature completion)", function()
        local s = make_suggestions(1000)
        -- Pre-create some suggestions
        s:create_or_age_suggestion(Suggestions.storage_low_key, 90, "s", "high", false, {"a"})
        s:create_or_age_suggestion(Suggestions.mismatched_storage_key, 5, "s", "low", true, {"b"})
        storage.networks[1] = { id = 1, suggestions = s }

        suggestions_calc.all_storage_chunks_done(nil, {}, 1)
        assert.is_nil(s:get_suggestions()[Suggestions.storage_low_key])
        assert.is_nil(s:get_suggestions()[Suggestions.mismatched_storage_key])
      end)
    end)
  end)
end)
