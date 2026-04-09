--- Integration tests for Logistics Insights
--- Runs end-to-end through LI's scan + analysis pipeline inside real Factorio

local helpers = require("tests.integration.helpers")
local NetworkBuilder = helpers.NetworkBuilder
local scheduler = require("scripts.scheduler")


-------------------------------------------------------------------------------
-- Scenario setup
-------------------------------------------------------------------------------

local function build_mixed_network(surface)
  local builder = NetworkBuilder.new(surface, {0, 0}, "player")

  builder:add_roboport({0, 0}, {bots = 20, quality = "normal"})
  if helpers.has_quality then
    builder:add_roboport({4, 0}, {bots = 10, quality = "uncommon"})
  else
    builder:add_roboport({4, 0}, {bots = 10})
  end

  builder:add_provider({8, 0}, {{"iron-plate", 500}, {"copper-plate", 200}})
  builder:add_provider({8, 4}, {{"iron-plate", 300}})
  builder:add_requester({-8, 0}, {{"iron-plate", 100, "normal"}})
  builder:add_requester({-8, 4}, {{"electronic-circuit", 50, "normal"}})
  builder:add_storage({0, 8})
  builder:add_buffer({0, -6}, {{"copper-plate", 25}})

  return builder
end

-------------------------------------------------------------------------------
-- Smoke test
-------------------------------------------------------------------------------

describe("Smoke test", function()
  test("single roboport forms a network that LI discovers", function()
    async(10000)
    local surface = game.surfaces[1]
    local eei = surface.create_entity{name = "electric-energy-interface", position = {50, 50}, force = "player"}
    local sub = surface.create_entity{name = "substation", position = {53, 50}, force = "player"}
    local rp = surface.create_entity{name = "roboport", position = {53, 54}, force = "player"}
    assert(eei and sub and rp, "Failed to create entities")
    rp.insert{name = "logistic-robot", count = 5}

    helpers.teleport_player({53, 54})

    after_ticks(200, function()
      local network = surface.find_logistic_network_by_position({53, 54}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI should have discovered the network")

      -- Cleanup
      eei.destroy(); sub.destroy(); rp.destroy()
      done()
    end)
  end)
end)

-------------------------------------------------------------------------------
-- Full pipeline tests
-------------------------------------------------------------------------------

describe("Mixed logistics network", function()
  local builder
  local start_tick

  before_each(function()
    -- Destroy any leftover entities from a previous failed test
    if builder then
      builder:destroy()
      builder = nil
    end
    -- Clear all player entities in the build area
    local surface = game.surfaces[1]
    local found = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(found) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end

    -- Clear LI's internal state from prior tests
    storage.networks = {}
    storage.fg_refreshing_network_id = nil
    storage.bg_refreshing_network_id = nil
    storage.analysing_networkdata = nil
    storage.analysing_network = nil
    storage.analysis_state = nil
    for _, pt in pairs(storage.players or {}) do
      pt.network = nil
      pt.fixed_network = false
    end
    scheduler.reset_phase()

    helpers.apply_settings({
      ["li-chunk-size-global"] = 400,
      ["li-chunk-processing-interval-ticks"] = 3,
      ["li-calculate-undersupply"] = true,
      ["li-gather-quality-data-global"] = true,
      ["li-show-all-networks"] = true,
      ["li-background-refresh-interval"] = 1,
      ["li-age-out-suggestions-interval-minutes"] = 3,
      ["li-ignore-player-demands-in-undersupply"] = true,
    })
    start_tick = game.tick
  end)

  after_each(function()
    if builder then
      builder:destroy()
      builder = nil
    end
  end)

  test("LI discovers the network and creates networkdata", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd then return end
      local rel = game.tick - start_tick
      helpers.record_budget("smoke discovery", rel, 11)
      assert.are_equal(network.network_id, nwd.id)
      done()
    end)
  end)

  test("bot counts converge after full scan cycle", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or (nwd.total_cells or 0) < 2 then return end
      local total_bots = helpers.sum_quality_table(nwd.total_bot_qualities)
      local idle = helpers.sum_quality_table(nwd.idle_bot_qualities)
      if total_bots < 30 or idle < 30 then return end

      local rel = game.tick - start_tick
      helpers.record_budget("bot counts converge", rel, 3102)
      assert.are_equal(30, total_bots)
      local charging = helpers.sum_quality_table(nwd.charging_bot_qualities)
      local waiting = helpers.sum_quality_table(nwd.waiting_bot_qualities)
      local delivering = helpers.sum_quality_table(nwd.delivering_bot_qualities)
      local picking = helpers.sum_quality_table(nwd.picking_bot_qualities)
      local other = helpers.sum_quality_table(nwd.other_bot_qualities)
      local state_sum = idle + charging + waiting + delivering + picking + other
      assert.are_equal(30, idle)
      assert.are_equal(0, charging)
      assert.are_equal(0, waiting)
      assert.are_equal(0, delivering)
      assert.are_equal(0, picking)
      assert.are_equal(0, other, "Expected no bots in 'other' state")
      assert.are_equal(total_bots, state_sum)
      done()
    end)
  end)

  test("deliveries are tracked for fulfillable requests", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd then return end
      -- Wait until bots have been counted and are all idle (deliveries done)
      local bot_items = nwd.bot_items
      if not bot_items then return end
      if (bot_items["logistic-robot-total"] or 0) < 30 then return end
      if (bot_items["logistic-robot-available"] or 0) < 30 then return end

      local rel = game.tick - start_tick
      helpers.record_budget("deliveries tracked", rel, 2981)
      assert.are_equal(30, bot_items["logistic-robot-total"])
      assert.are_equal(30, bot_items["logistic-robot-available"])
      assert.are_equal(0, bot_items["charging-robot"])
      assert.are_equal(0, bot_items["waiting-for-charge-robot"])
      assert.are_equal(0, table_size(nwd.bot_deliveries))
      assert.are_equal(0, table_size(nwd.delivery_history))
      done()
    end)
  end)

  test("undersupply analysis completes", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or not nwd.last_analysed_tick or nwd.last_analysed_tick <= start_tick then return end
      -- Wait for storage analysis and suggestions to complete
      if (nwd.storage_count or 0) < 1 then return end
      local suggestions = nwd.suggestions:get_suggestions()
      if not suggestions["too-few-bots"] then return end

      local rel = game.tick - start_tick
      helpers.record_budget("undersupply analysis", rel, 569)
      assert.are_equal(3, nwd.requester_count)
      -- 7 = 2 passive-providers + 1 storage + 1 buffer + 2 roboports + 2 requesters - 1 storage
      -- network.providers includes all entities that can provide items to the network
      assert.are_equal(7, nwd.provider_count)
      assert.are_equal(1, nwd.storage_count)

      assert.are_equal(100, suggestions["too-few-bots"].count)
      assert.are_equal("entity/logistic-robot", suggestions["too-few-bots"].sprite)
      done()
    end)
  end)

  if helpers.has_quality then
    test("quality data tracked when Space Age is active", function()
      async(10000)
      builder = build_mixed_network(game.surfaces[1])
      builder:build()
      helpers.teleport_player({0, 0})

      on_tick(function()
        local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd or (nwd.total_cells or 0) < 2 then return end
        if not (nwd.roboport_qualities or {})["uncommon"] then return end

        local rel = game.tick - start_tick
        helpers.record_budget("quality data", rel, 121)
        assert.are_equal(1, nwd.roboport_qualities["normal"])
        assert.are_equal(1, nwd.roboport_qualities["uncommon"])
        assert.are_equal(20, (nwd.total_bot_qualities or {})["normal"] or 0)
        assert.are_equal(10, (nwd.total_bot_qualities or {})["uncommon"] or 0)
        done()
      end)
    end)
  end

  test("cell data populated after scan", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or (nwd.total_cells or 0) < 2 then return end

      local rel = game.tick - start_tick
      helpers.record_budget("cell data populated", rel, 121)
      assert.are_equal(2, nwd.total_cells)
      assert.are_equal(2, helpers.sum_quality_table(nwd.roboport_qualities))
      assert.are_equal(0, #(nwd.unpowered_roboport_list or {}))
      done()
    end)
  end)

  test("provider and storage counts populated", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or not nwd.last_analysed_tick or nwd.last_analysed_tick <= start_tick then return end
      if (nwd.storage_count or 0) < 1 then return end

      local rel = game.tick - start_tick
      helpers.record_budget("provider/storage counts", rel, 218)
      assert.are_equal(7, nwd.provider_count)
      assert.are_equal(1, nwd.storage_count)
      done()
    end)
  end)
end)

-------------------------------------------------------------------------------
-- Settings variation
-------------------------------------------------------------------------------

describe("Settings: chunk size variation", function()
  local builder

  before_each(function()
    if builder then
      builder:destroy()
      builder = nil
    end
    local surface = game.surfaces[1]
    local entities = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(entities) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end)

  after_each(function()
    if builder then
      builder:destroy()
      builder = nil
    end
  end)

  test("small chunk size (50) produces valid results", function()
    async(10000)
    helpers.apply_settings({
      ["li-chunk-size-global"] = 50,
      ["li-chunk-processing-interval-ticks"] = 3,
      ["li-calculate-undersupply"] = true,
      ["li-gather-quality-data-global"] = true,
      ["li-show-all-networks"] = true,
      ["li-background-refresh-interval"] = 1,
      ["li-age-out-suggestions-interval-minutes"] = 3,
      ["li-ignore-player-demands-in-undersupply"] = true,
    })

    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})
    local t0 = game.tick

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or (nwd.total_cells or 0) < 2 then return end
      if helpers.sum_quality_table(nwd.total_bot_qualities) < 30 then return end

      local rel = game.tick - t0
      helpers.record_budget("chunk_size=50", rel, 154)
      assert.are_equal(30, helpers.sum_quality_table(nwd.total_bot_qualities))
      assert.are_equal(2, nwd.total_cells)
      done()
    end)
  end)

  test("large chunk size (10000) produces valid results", function()
    async(10000)
    helpers.apply_settings({
      ["li-chunk-size-global"] = 10000,
      ["li-chunk-processing-interval-ticks"] = 3,
      ["li-calculate-undersupply"] = true,
      ["li-gather-quality-data-global"] = true,
      ["li-show-all-networks"] = true,
      ["li-background-refresh-interval"] = 1,
      ["li-age-out-suggestions-interval-minutes"] = 3,
      ["li-ignore-player-demands-in-undersupply"] = true,
    })

    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})
    local t0 = game.tick

    on_tick(function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      if not network or not network.valid then return end
      local nwd = storage.networks and storage.networks[network.network_id]
      if not nwd or (nwd.total_cells or 0) < 2 then return end
      if helpers.sum_quality_table(nwd.total_bot_qualities) < 30 then return end

      local rel = game.tick - t0
      helpers.record_budget("chunk_size=10000", rel, 141)
      assert.are_equal(30, helpers.sum_quality_table(nwd.total_bot_qualities))
      assert.are_equal(2, nwd.total_cells)
      done()
    end)
  end)
end)

-------------------------------------------------------------------------------
-- Dynamic scenarios: test behavior changes during the simulation
-------------------------------------------------------------------------------

describe("Dynamic scenarios", function()
  local entities = {}

  before_each(function()
    local surface = game.surfaces[1]
    -- Clear all player entities in the build area, plus any stray bots on the entire surface
    local found = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(found) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    local stray_bots = surface.find_entities_filtered{type = {"logistic-robot", "construction-robot"}}
    for _, e in pairs(stray_bots) do
      if e.valid then e.destroy() end
    end
    entities = {}

    -- Clear LI's internal network state from prior tests
    storage.networks = {}
    storage.fg_refreshing_network_id = nil
    storage.bg_refreshing_network_id = nil
    storage.analysing_networkdata = nil
    storage.analysing_network = nil
    storage.analysis_state = nil
    -- Reset player network reference so LI re-discovers from scratch
    for _, pt in pairs(storage.players or {}) do
      pt.network = nil
      pt.fixed_network = false
    end

    -- Reset scheduler phase so task timing is relative to this tick, not absolute
    scheduler.reset_phase()

    helpers.apply_settings({
      ["li-chunk-size-global"] = 400,
      ["li-chunk-processing-interval-ticks"] = 3,
      ["li-calculate-undersupply"] = true,
      ["li-gather-quality-data-global"] = true,
      ["li-show-all-networks"] = true,
      ["li-background-refresh-interval"] = 1,
      ["li-age-out-suggestions-interval-minutes"] = 3,
      ["li-ignore-player-demands-in-undersupply"] = true,
    })
  end)

  after_each(function()
    for _, e in pairs(entities) do
      if e.valid then e.destroy() end
    end
    entities = {}
  end)

  test("unpowered roboport suggestion appears and ages out when power restored", function()
    async(15000)
    local surface = game.surfaces[1]
    local t0 = game.tick  -- all timings relative to this

    -- Build 2 roboports with separate power paths:
    -- EEI + Substation A powers roboport A directly (within 9-tile supply)
    -- Substation B powers roboport B, connected via wire to substation A (within 18-tile reach)
    -- Destroying substation B unpowers only roboport B
    local eei = surface.create_entity{name = "electric-energy-interface", position = {-3, -3}, force = "player"}
    local substation_a = surface.create_entity{name = "substation", position = {0, -3}, force = "player"}
    local rp_a = surface.create_entity{name = "roboport", position = {0, 0}, force = "player"}
    local rp_b = surface.create_entity{name = "roboport", position = {14, 0}, force = "player"}
    local pole = surface.create_entity{name = "substation", position = {14, -3}, force = "player"}
    assert(eei and substation_a and pole and rp_a and rp_b, "Failed to create entities")

    rp_a.insert{name = "logistic-robot", count = 5}
    rp_b.insert{name = "logistic-robot", count = 5}

    entities = {eei, substation_a, pole, rp_a, rp_b}

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_discovery"
    local pole_destroyed_at   -- relative tick when pole was destroyed
    local pole_rebuilt_at     -- relative tick when pole was rebuilt

    on_tick(function()
      local rel = game.tick - t0  -- ticks since test start

      -- Phase 0: Wait for LI to discover the network AND complete a full scan
      if phase == "wait_for_discovery" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if network and network.valid then
          local nwd = storage.networks and storage.networks[network.network_id]
          if nwd and (nwd.total_cells or 0) >= 2 then
            network_id = network.network_id

            -- Phase 1: Verify both roboports powered, no unpowered suggestion
            assert.are_equal(2, nwd.total_cells)
            assert.are_equal(0, #(nwd.unpowered_roboport_list or {}))
            local suggestions = nwd.suggestions:get_suggestions()
            assert(not suggestions["unpowered-roboports"],
              "Should have no unpowered-roboports suggestion when all powered")

            -- Network discovery + first scan should complete within ~133 ticks
            helpers.record_budget("unpowered: discovery", rel, 133)

            -- Destroy the pole to unpower roboport B
            pole.destroy()
            pole_destroyed_at = rel
            phase = "wait_for_unpowered"
          end
        end
        return
      end

      -- Phase 2: Poll for unpowered roboport detection
      if phase == "wait_for_unpowered" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()

        if suggestions["unpowered-roboports"] then
          local detect_time = rel - pole_destroyed_at

          assert.are_equal(1, suggestions["unpowered-roboports"].count)
          assert.are_equal("high", suggestions["unpowered-roboports"].urgency)
          -- Detection should happen within ~271 ticks (cell scan + analysis cycle)
          helpers.record_budget("unpowered: detection", detect_time, 271)

          -- Restore power by rebuilding the pole
          pole = surface.create_entity{name = "substation", position = {14, -3}, force = "player"}
          table.insert(entities, pole)
          pole_rebuilt_at = rel
          phase = "wait_for_repowered"
          return
        end
        return
      end

      -- Phase 3: Poll for repowered — suggestion ages out or disappears
      if phase == "wait_for_repowered" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local unpowered_count = #(nwd.unpowered_roboport_list or {})
        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["unpowered-roboports"]

        if unpowered_count == 0 and (not s or s.urgency == "aging") then
          local recovery_time = rel - pole_rebuilt_at

          -- Recovery should happen within ~226 ticks
          helpers.record_budget("unpowered: recovery", recovery_time, 226)
          done()
        end
        return
      end
    end)
  end)

  test("delivery tracking over time with changing supply", function()
    async(30000)
    local surface = game.surfaces[1]
    local t0 = game.tick

    -- Network: 1 roboport with 10 bots, 1 requester wanting 100 iron-plate, NO providers yet
    local eei = surface.create_entity{name = "electric-energy-interface", position = {-3, -3}, force = "player"}
    local sub = surface.create_entity{name = "substation", position = {0, -3}, force = "player"}
    local rp = surface.create_entity{name = "roboport", position = {0, 0}, force = "player"}
    local requester = surface.create_entity{name = "requester-chest", position = {-5, 0}, force = "player"}
    assert(eei and sub and rp and requester, "Failed to create entities")

    rp.insert{name = "logistic-robot", count = 10}

    -- Set request filter: 100 iron-plate
    local point = requester.get_logistic_point(defines.logistic_member_index.logistic_container)
    local section = point.get_section(1)
    section.set_slot(1, {value = {type = "item", name = "iron-plate", quality = "normal"}, min = 100})

    entities = {eei, sub, rp, requester}

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_undersupply"
    local provider_a, provider_b  -- placed during test

    --- Find an undersupply item by name in the cached list
    local function find_undersupply(nwd, item_name)
      local list = nwd.suggestions:get_cached_list("undersupply") or {}
      for _, item in ipairs(list) do
        if item.item_name == item_name then return item end
      end
      return nil
    end

    on_tick(function()
      local rel = game.tick - t0

      -- Phase 0: Wait for undersupply to be detected (no providers yet)
      if phase == "wait_for_undersupply" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        -- Drive scan + analysis synchronously each tick so we sample fresh
        -- state regardless of the production scheduler's slow background
        -- cadence (which can alias with bot delivery cycles).
        helpers.run_full_scan(network.network_id)
        helpers.run_full_analysis(network.network_id)

        local us = find_undersupply(nwd, "iron-plate")
        if us then
          network_id = network.network_id
          -- Undersupply: 100 requested, 0 supplied, nothing in transit
          assert.are_equal(100, us.shortage)
          assert.are_equal(0, us.supply)
          assert.are_equal(100, us.request)
          assert.are_equal(0, us.under_way)
          assert.are_equal(0, nwd.bot_items["delivering"] or 0)
          helpers.record_budget("delivery: phase 0 (initial undersupply)", rel, 196)

          -- Place provider with 50 iron-plate (half the demand)
          provider_a = surface.create_entity{name = "passive-provider-chest", position = {5, 0}, force = "player"}
          provider_a.get_inventory(defines.inventory.chest).insert{name = "iron-plate", count = 50}
          table.insert(entities, provider_a)

          phase = "wait_for_picking"
        end
        return
      end

      -- Phase 1a: Wait for bots to start picking up items. With deterministic
      -- per-tick scanning we catch the transition the moment the first bot
      -- enters the picking state, so picking is typically 1-N (not 10) — the
      -- other bots are still in flight to the provider.
      if phase == "wait_for_picking" then
        helpers.run_full_scan(network_id)
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local picking = nwd.bot_items["picking"] or 0
        if picking > 0 then
          assert(picking <= 10, "picking " .. picking .. " > 10")
          assert.are_equal(0, nwd.bot_items["delivering"] or 0)
          helpers.record_budget("delivery: phase 1a (picking)", rel, 223)
          phase = "wait_for_delivering"
        end
        return
      end

      -- Phase 1b: Wait for bots to start delivering. Same caveat as Phase 1a
      -- — we catch the first transition, so delivering may be 1-N rather than
      -- a clean 10. The invariant is: at least one delivering, accounting
      -- balances (picking + delivering ≤ 10).
      if phase == "wait_for_delivering" then
        helpers.run_full_scan(network_id)
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local delivering = nwd.bot_items["delivering"] or 0
        if delivering > 0 then
          local picking = nwd.bot_items["picking"] or 0
          assert(picking + delivering <= 10, "picking+delivering " .. (picking + delivering) .. " > 10")
          local bd = nwd.bot_deliveries["iron-plate:normal"]
          assert(bd, "Expected iron-plate in bot_deliveries")
          assert.are_equal(delivering, bd.count)
          helpers.record_budget("delivery: phase 1b (delivering)", rel, 344)
          phase = "wait_for_partial_undersupply"
        end
        return
      end

      -- Phase 2: Wait for undersupply to reflect partial supply. With per-tick
      -- sampling we catch the transition early, so the breakdown of supply vs
      -- under_way depends on which exact instant we catch. The invariant is:
      -- shortage strictly decreased from 100 (LI saw the new provider), and
      -- the accounting balances.
      if phase == "wait_for_partial_undersupply" then
        helpers.run_full_scan(network_id)
        helpers.run_full_analysis(network_id)
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local us = find_undersupply(nwd, "iron-plate")
        if us and us.shortage < 100 then
          assert.are_equal(100, us.request)
          assert.are_equal(100, us.shortage + us.supply + us.under_way)
          helpers.record_budget("delivery: phase 2 (partial undersupply)", rel, 423)

          -- Add excess supply (200 more iron-plate)
          provider_b = surface.create_entity{name = "passive-provider-chest", position = {5, 4}, force = "player"}
          provider_b.get_inventory(defines.inventory.chest).insert{name = "iron-plate", count = 200}
          table.insert(entities, provider_b)

          phase = "wait_for_no_undersupply"
        end
        return
      end

      -- Phase 3: Wait for undersupply to disappear
      if phase == "wait_for_no_undersupply" then
        helpers.run_full_scan(network_id)
        helpers.run_full_analysis(network_id)
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local us = find_undersupply(nwd, "iron-plate")
        if not us then
          helpers.record_budget("delivery: phase 3 (no undersupply)", rel, 637)
          phase = "wait_for_idle"
        end
        return
      end

      -- Phase 4: Wait for all bots to finish delivering
      if phase == "wait_for_idle" then
        helpers.run_full_scan(network_id)
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local delivering = nwd.bot_items["delivering"] or 0
        if delivering == 0 then
          helpers.record_budget("delivery: phase 4 (history)", rel, 638)
          done()
        end
        return
      end
    end)
  end)
end)

-------------------------------------------------------------------------------
-- Suggestion lifecycle: trigger → detect → fix → resolve
-------------------------------------------------------------------------------

describe("Suggestion lifecycle", function()
  local builder

  before_each(function()
    if builder then
      builder:destroy()
      builder = nil
    end
    local surface = game.surfaces[1]
    local found = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(found) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    local stray_bots = surface.find_entities_filtered{type = {"logistic-robot", "construction-robot"}}
    for _, e in pairs(stray_bots) do
      if e.valid then e.destroy() end
    end

    storage.networks = {}
    storage.fg_refreshing_network_id = nil
    storage.bg_refreshing_network_id = nil
    storage.analysing_networkdata = nil
    storage.analysing_network = nil
    storage.analysis_state = nil
    for _, pt in pairs(storage.players or {}) do
      pt.network = nil
      pt.fixed_network = false
    end
    scheduler.reset_phase()

    helpers.apply_settings({
      ["li-chunk-size-global"] = 400,
      ["li-chunk-processing-interval-ticks"] = 3,
      ["li-calculate-undersupply"] = true,
      ["li-gather-quality-data-global"] = true,
      ["li-show-all-networks"] = true,
      ["li-background-refresh-interval"] = 1,
      ["li-age-out-suggestions-interval-minutes"] = 3,
      ["li-ignore-player-demands-in-undersupply"] = true,
    })
  end)

  after_each(function()
    if builder then
      builder:destroy()
      builder = nil
    end
    game.surfaces[1].always_day = false
  end)

  test("insufficient-storage appears when storage > 70% full and ages out when capacity added", function()
    async(10000)
    local surface = game.surfaces[1]

    -- 1 roboport, 1 storage chest with 35/48 slots used (72.9% > 70% threshold)
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 5})
    builder:add_storage({4, 4}, {{"iron-plate", 3500}})  -- 35 stacks of 100
    builder:build()

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_suggestion"

    on_tick(function()
      if phase == "wait_for_suggestion" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["insufficient-storage"]
        if not s then return end

        network_id = network.network_id
        assert.are_equal("entity/storage-chest", s.sprite)
        assert.are_equal("low", s.urgency)  -- 72.9% < 90% threshold
        assert(s.count > 70, "Expected capacity > 70%, got " .. tostring(s.count))
        assert(s.count < 80, "Expected capacity < 80%, got " .. tostring(s.count))

        -- Unfiltered storage should also fire (chest has no filter)
        local us = suggestions["insufficient-unfiltered-storage"]
        assert.is_not_nil(us, "Unfiltered storage suggestion should also fire")

        -- Fix: add an empty storage chest to drop capacity to 35/96 = 36.5%
        local extra = surface.create_entity{
          name = "storage-chest", position = {6, 4}, force = "player"
        }
        assert(extra, "Failed to create rescue storage")
        -- Track via builder so after_each cleans it up
        table.insert(builder._entities, extra)

        phase = "wait_for_aging"
        return
      end

      if phase == "wait_for_aging" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["insufficient-storage"]
        local us = suggestions["insufficient-unfiltered-storage"]
        if (not s or s.urgency == "aging") and (not us or us.urgency == "aging") then
          done()
        end
        return
      end
    end)
  end)

  test("insufficient-storage with high urgency when storage > 90% full", function()
    async(10000)
    local surface = game.surfaces[1]

    -- 1 roboport, 1 storage chest with 44/48 slots used (91.7% > 90% threshold)
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 5})
    builder:add_storage({4, 4}, {{"iron-plate", 4400}})  -- 44 stacks of 100
    builder:build()

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_suggestion"

    on_tick(function()
      if phase == "wait_for_suggestion" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["insufficient-storage"]
        if not s then return end

        network_id = network.network_id
        assert.are_equal("entity/storage-chest", s.sprite)
        assert.are_equal("high", s.urgency)  -- 91.7% > 90% threshold
        assert(s.count > 90, "Expected capacity > 90%, got " .. tostring(s.count))

        -- Fix: add two empty storage chests to drop capacity to 44/144 = 30.6%
        for _, pos in pairs({{6, 4}, {8, 4}}) do
          local extra = surface.create_entity{
            name = "storage-chest", position = pos, force = "player"
          }
          assert(extra, "Failed to create rescue storage")
          table.insert(builder._entities, extra)
        end

        phase = "wait_for_aging"
        return
      end

      if phase == "wait_for_aging" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["insufficient-storage"]
        if not s or s.urgency == "aging" then
          done()
        end
        return
      end
    end)
  end)

  test("mismatched-storage appears when filtered chest has wrong items and ages out when cleared", function()
    async(10000)
    local surface = game.surfaces[1]

    -- 1 roboport, 1 storage chest filtered for iron-plate but filled with copper-plate
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 5})
    builder:add_storage({4, 4}, {{"copper-plate", 500}}, {filter = {name = "iron-plate"}})
    builder:build()

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_suggestion"

    on_tick(function()
      if phase == "wait_for_suggestion" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["mismatched-storage"]
        if not s then return end

        network_id = network.network_id
        assert.are_equal(1, s.count)
        assert.are_equal("entity/storage-chest", s.sprite)
        assert.are_equal("low", s.urgency)  -- mismatched is always low

        -- Fix: find the mismatched chest and clear its inventory
        local chests = surface.find_entities_filtered{
          name = "storage-chest", area = {{3, 3}, {5, 5}}, force = "player"
        }
        assert(#chests > 0, "Could not find storage chest to clear")
        chests[1].get_inventory(defines.inventory.chest).clear()

        phase = "wait_for_aging"
        return
      end

      if phase == "wait_for_aging" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["mismatched-storage"]
        if not s or s.urgency == "aging" then
          done()
        end
        return
      end
    end)
  end)

  test("too-few-bots appears when all bots busy and ages out when demand removed", function()
    async(10000)
    local surface = game.surfaces[1]

    -- 1 roboport with 10 bots, provider with iron, requester wanting 100 iron-plate
    -- High demand relative to bot count keeps all bots busy (idle <= 2%)
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 10})
    builder:add_provider({8, 0}, {{"iron-plate", 500}})
    builder:add_requester({-8, 0}, {{"iron-plate", 100, "normal"}})
    builder:build()

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_suggestion"

    on_tick(function()
      if phase == "wait_for_suggestion" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["too-few-bots"]
        if not s then return end

        network_id = network.network_id
        assert.are_equal("entity/logistic-robot", s.sprite)
        assert.are_equal("low", s.urgency)  -- too-few-bots is always low
        assert(s.count >= 90, "Expected busy% >= 90, got " .. tostring(s.count))

        -- Fix: destroy the requester so bots go idle
        local requesters = surface.find_entities_filtered{
          name = "requester-chest", force = "player"
        }
        for _, r in pairs(requesters) do
          if r.valid then r.destroy() end
        end

        phase = "wait_for_aging"
        return
      end

      if phase == "wait_for_aging" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["too-few-bots"]
        if not s or s.urgency == "aging" then
          done()
        end
        return
      end
    end)
  end)

  test("too-many-bots appears with rising idle count and clears when bots removed", function()
    async(15000)
    local surface = game.surfaces[1]

    -- 1 roboport with 100 bots (at the threshold), no demand — all idle
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 100})
    builder:build()

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_discovery"
    local roboport

    on_tick(function()
      -- Phase 0: wait for network discovery and initial scan
      if phase == "wait_for_discovery" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd or (nwd.total_cells or 0) < 1 then return end

        network_id = network.network_id

        -- Find the roboport to manipulate bot count
        local rps = surface.find_entities_filtered{
          name = "roboport", force = "player"
        }
        assert(#rps > 0, "Could not find roboport")
        roboport = rps[1]

        phase = "wait_for_suggestion"
        return
      end

      -- Phase 1: gradually grow the bot count so analysis sees a sustained rising trend.
      -- Insert 5 bots every 60 game ticks until ~250 total (well below the ~350-bot
      -- roboport capacity, so growth never plateaus). Per-tick inserts grow too fast:
      -- the network reaches capacity before enough analysis samples accumulate, leaving
      -- the BOT_TREND_WINDOW_TICKS history full of identical plateau values and failing
      -- the `last > first` trend check in suggestions_calc.analyse_too_many_bots.
      if phase == "wait_for_suggestion" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        if (game.tick % 60) == 0 then
          local current = roboport.get_inventory(defines.inventory.roboport_robot).get_item_count()
          if current < 250 then
            roboport.insert{name = "logistic-robot", count = 5}
          end
        end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["too-many-bots"]
        if not s then return end

        assert.are_equal("entity/logistic-robot", s.sprite)
        assert.are_equal("high", s.urgency)  -- 100% idle > 80% threshold

        -- Fix: remove bots to bring total below 100 (MIN_TOTAL_BOTS_FOR_SUGGESTION)
        -- This triggers the clear_suggestion path immediately
        local total = roboport.get_inventory(defines.inventory.roboport_robot).get_item_count()
        roboport.remove_item{name = "logistic-robot", count = total - 50}

        phase = "wait_for_cleared"
        return
      end

      -- Phase 2: wait for suggestion to be cleared
      if phase == "wait_for_cleared" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        if not suggestions["too-many-bots"] then
          done()
        end
        return
      end
    end)
  end)

  test("waiting-to-charge appears with charging congestion and ages out when power restored", function()
    async(30000)
    local surface = game.surfaces[1]
    surface.always_day = true  -- ensure solar panel produces power

    -- Network with 50 bots and high demand, but only a solar panel for power (60 kW).
    -- A roboport needs ~4 MW for 4 charging pads, so charging is severely throttled.
    -- Bots deplete energy delivering items and queue up waiting to charge.
    builder = NetworkBuilder.new(surface, {0, 0}, "player")
    builder:add_roboport({0, 0}, {bots = 50})
    builder:add_provider({8, 0}, {{"iron-plate", 10000}})
    builder:add_requester({-8, 0}, {{"iron-plate", 5000, "normal"}})
    builder:build()

    -- Replace EEI (infinite power) with solar panel (60 kW) to throttle charging
    local eeis = surface.find_entities_filtered{
      name = "electric-energy-interface", area = {{-5, -5}, {5, 5}}, force = "player"
    }
    for _, e in pairs(eeis) do e.destroy() end
    local solar = surface.create_entity{
      name = "solar-panel", position = {-3, -3}, force = "player"
    }
    assert(solar, "Failed to create solar panel")
    table.insert(builder._entities, solar)

    helpers.teleport_player({0, 0})

    local network_id
    local phase = "wait_for_suggestion"

    on_tick(function()
      -- Phase 0: wait for suggestion (needs ~9000 ticks of history with >9 bots waiting)
      if phase == "wait_for_suggestion" then
        local network = surface.find_logistic_network_by_position({0, 0}, "player")
        if not network or not network.valid then return end
        local nwd = storage.networks and storage.networks[network.network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["waiting-to-charge"]
        if not s then return end

        network_id = network.network_id
        assert.are_equal("entity/roboport", s.sprite)
        assert(s.count > 0, "Expected suggested roboports > 0, got " .. tostring(s.count))

        -- Fix: restore full power by adding an EEI (within substation wire reach)
        local eei = surface.create_entity{
          name = "electric-energy-interface", position = {-6, -3}, force = "player"
        }
        assert(eei, "Failed to create EEI for fix")
        table.insert(builder._entities, eei)

        phase = "wait_for_aging"
        return
      end

      -- Phase 1: wait for suggestion to age out (bots charge quickly with full power)
      if phase == "wait_for_aging" then
        local nwd = storage.networks[network_id]
        if not nwd then return end

        local suggestions = nwd.suggestions:get_suggestions()
        local s = suggestions["waiting-to-charge"]
        if not s or s.urgency == "aging" then
          surface.always_day = false
          done()
        end
        return
      end
    end)
  end)
end)
