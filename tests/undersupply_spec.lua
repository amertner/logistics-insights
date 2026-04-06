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

  --- Build a mock requester entity with logistic point sections
  local function make_requester(opts)
    opts = opts or {}
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
end)
