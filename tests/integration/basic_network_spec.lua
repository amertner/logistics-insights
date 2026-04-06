--- Integration tests for Logistics Insights
--- Runs end-to-end through LI's scan + analysis pipeline inside real Factorio

local helpers = require("tests.integration.helpers")
local NetworkBuilder = helpers.NetworkBuilder

-- Timing constants (in ticks)
local NETWORK_DISCOVERY_WAIT = 200   -- enough for network to form + LI to discover
local ANALYSIS_WAIT = 5000           -- enough for full scan + analysis cycle

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

    after_ticks(NETWORK_DISCOVERY_WAIT, function()
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
    -- Clear all entities in the build area to avoid accumulation
    local surface = game.surfaces[1]
    local entities = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(entities) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end

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

    after_ticks(NETWORK_DISCOVERY_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not create networkdata for network " .. tostring(network.network_id))
      assert.are_equal(network.network_id, nwd.id)
      done()
    end)
  end)

  test("bot counts converge after full scan cycle", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

      local total_bots = helpers.sum_quality_table(nwd.total_bot_qualities)
      assert.are_equal(total_bots, 30)

      local idle = helpers.sum_quality_table(nwd.idle_bot_qualities)
      local charging = helpers.sum_quality_table(nwd.charging_bot_qualities)
      local waiting = helpers.sum_quality_table(nwd.waiting_bot_qualities)
      local delivering = helpers.sum_quality_table(nwd.delivering_bot_qualities)
      local picking = helpers.sum_quality_table(nwd.picking_bot_qualities)
      local other = helpers.sum_quality_table(nwd.other_bot_qualities)
      local state_sum = idle + charging + waiting + delivering + picking + other
      assert.are_equal(idle, 30)
      assert.are_equal(charging, 0)
      assert.are_equal(waiting, 0)
      assert.are_equal(delivering, 0)
      assert.are_equal(picking, 0)
      assert.are_equal(other, 0, "Expected no bots in 'other' state")

      assert.are_equal(total_bots, state_sum,
        "Bot state sum (" .. state_sum .. ") should equal total (" .. total_bots .. ")")
      done()
    end)
  end)

  test("deliveries are tracked for fulfillable requests", function()
    async(10000)
    builder = build_mixed_network(game.surfaces[1])
    builder:build()
    helpers.teleport_player({0, 0})

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

      assert.are_equal(30, helpers.sum_quality_table(nwd.total_bot_qualities))

      -- By tick 5200, all iron-plate deliveries have completed; bots are idle
      local bot_items = nwd.bot_items
      assert.are_equal(30, bot_items["logistic-robot-total"])
      assert.are_equal(30, bot_items["logistic-robot-available"])
      assert.are_equal(0, bot_items["delivering"])
      assert.are_equal(0, bot_items["picking"])
      assert.are_equal(0, bot_items["charging-robot"])
      assert.are_equal(0, bot_items["waiting-for-charge-robot"])

      -- Deliveries completed before this check, so both tables are empty
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

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

      assert(nwd.last_analysed_tick > start_tick, "Analysis should have completed")
      -- 3 = 2 requester chests + 1 buffer chest (buffer chests are in network.requesters)
      assert.are_equal(3, nwd.requester_count)
      -- 4 = 2 passive-providers + 1 storage + 1 buffer (all in network.providers)
      assert.are_equal(4, nwd.provider_count)
      assert.are_equal(1, nwd.storage_count)

      -- Suggestions: "too-few-bots" is generated (100 iron-plate requested, 30 bots)
      local suggestions = nwd.suggestions:get_suggestions()
      assert(suggestions["too-few-bots"], "Expected too-few-bots suggestion")
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

      after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
        local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
        assert(network and network.valid, "Network did not form")
        local nwd = storage.networks[network.network_id]
        assert(nwd, "LI did not discover the network")

        -- Expected: 1 normal roboport, 1 uncommon roboport
        assert.are_equal(1, (nwd.roboport_qualities or {})["normal"] or 0)
        assert.are_equal(1, (nwd.roboport_qualities or {})["uncommon"] or 0)

        -- Expected: 20 normal bots, 10 uncommon bots
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

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

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

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

      -- 4 = 2 passive-providers + 1 storage + 1 buffer (all are in network.providers)
      assert.are_equal(4, nwd.provider_count)
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

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

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

    after_ticks(NETWORK_DISCOVERY_WAIT + ANALYSIS_WAIT, function()
      local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
      assert(network and network.valid, "Network did not form")
      local nwd = storage.networks[network.network_id]
      assert(nwd, "LI did not discover the network")

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
    local found = surface.find_entities_filtered{area = {{-20, -20}, {20, 20}}, force = "player"}
    for _, e in pairs(found) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    entities = {}

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
            assert(rel <= 133, "Discovery took too long: " .. rel .. " ticks (expected <= 133)")

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
          assert(detect_time <= 271,
            "Unpowered detection took too long: " .. detect_time .. " ticks (expected <= 271)")

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
          assert(recovery_time <= 226,
            "Recovery took too long: " .. recovery_time .. " ticks (expected <= 226)")
          done()
        end
        return
      end
    end)
  end)
end)
