local mock = require("tests.mocks.factorio")

describe("Suggestions", function()
  local Suggestions

  before_each(function()
    mock.fresh()
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
      age_out_suggestions_interval_minutes = 5,
    }
    Suggestions = require("scripts.suggestions")
  end)

  describe("new()", function()
    it("creates with zero tick and empty tables", function()
      local s = Suggestions.new()
      assert.are.equal(0, s._current_tick)
      assert.are.equal(0, s:get_current_count())
    end)
  end)

  describe("get_urgency()", function()
    it("returns high when value exceeds threshold", function()
      local s = Suggestions.new()
      assert.are.equal("high", s:get_urgency(0.95, 0.9))
    end)

    it("returns low when value is at or below threshold", function()
      local s = Suggestions.new()
      assert.are.equal("low", s:get_urgency(0.9, 0.9))
      assert.are.equal("low", s:get_urgency(0.5, 0.9))
    end)
  end)

  describe("create_or_age_suggestion()", function()
    it("creates a suggestion when count > 0", function()
      local s = Suggestions.new()
      s:create_or_age_suggestion("test-key", 5, "entity/roboport", "high", true, {"action text"})
      local suggestions = s:get_suggestions()
      assert.is_not_nil(suggestions["test-key"])
      assert.are.equal("high", suggestions["test-key"].urgency)
      assert.are.equal(5, suggestions["test-key"].count)
      assert.are.equal("test-key", suggestions["test-key"].clickname)
    end)

    it("sets clickname to nil when not clickable", function()
      local s = Suggestions.new()
      s:create_or_age_suggestion("test-key", 5, "entity/roboport", "low", false, {"action"})
      assert.is_nil(s:get_suggestions()["test-key"].clickname)
    end)

    it("ages out when count is 0", function()
      local s = Suggestions.new()
      s._current_tick = 1000
      -- Create first
      s:create_or_age_suggestion("test-key", 5, "entity/roboport", "high", false, {"action"})
      -- Now age it
      s:create_or_age_suggestion("test-key", 0, "entity/roboport", "high", false, {"action"})
      local suggestion = s:get_suggestions()["test-key"]
      assert.are.equal("aging", suggestion.urgency)
    end)
  end)

  describe("remember() and history", function()
    it("stores history entries with tick", function()
      local s = Suggestions.new()
      s._current_tick = 100
      s:remember("key1", 42)
      s._current_tick = 200
      s:remember("key1", 55)
      local history = s._historydata["key1"]
      assert.are.equal(2, #history)
      assert.are.equal(100, history[1].tick)
      assert.are.equal(42, history[1].data)
      assert.are.equal(200, history[2].tick)
      assert.are.equal(55, history[2].data)
    end)
  end)

  describe("max_from_history()", function()
    it("returns the maximum value within the window", function()
      local s = Suggestions.new()
      s._current_tick = 100
      s:remember("k", 10)
      s._current_tick = 200
      s:remember("k", 30)
      s._current_tick = 250
      s:remember("k", 20)
      assert.are.equal(30, s:max_from_history("k"))
    end)

    it("prunes entries older than 5 seconds (300 ticks)", function()
      local s = Suggestions.new()
      s._current_tick = 10
      s:remember("k", 99)
      s._current_tick = 500
      s:remember("k", 5)
      -- Current tick is 500, cutoff is 500-300=200, so tick=10 is pruned
      assert.are.equal(5, s:max_from_history("k"))
      assert.are.equal(1, #s._historydata["k"])
    end)

    it("returns 0 for unknown key", function()
      local s = Suggestions.new()
      assert.are.equal(0, s:max_from_history("nonexistent"))
    end)
  end)

  describe("weighted_min_from_history()", function()
    it("returns 0 with fewer than 2 data points", function()
      local s = Suggestions.new()
      s._current_tick = 100
      s:remember("k", 10)
      assert.are.equal(0, s:weighted_min_from_history("k", 60))
    end)

    it("returns 0 when not enough time has passed", function()
      local s = Suggestions.new()
      s._current_tick = 100
      s:remember("k", 10)
      s._current_tick = 200
      s:remember("k", 20)
      -- need_time_seconds=60 -> cutoff = 200 - 3600 = -3400
      -- history[1].tick=100 > cutoff+delta, so not enough data
      -- Actually: cutoff = 200 - 60*60 = -3400, history[1].tick=100 > -3400+100=-3300? yes
      -- Let's use a tighter window
      assert.are.equal(0, s:weighted_min_from_history("k", 1))
    end)

    it("returns 0 when multiple zeros in history", function()
      local s = Suggestions.new()
      for i = 1, 10 do
        s._current_tick = i * 100
        s:remember("k", 0)
      end
      assert.are.equal(0, s:weighted_min_from_history("k", 60))
    end)
  end)

  describe("age_out_suggestion()", function()
    it("sets urgency to aging on first call", function()
      local s = Suggestions.new()
      s._current_tick = 1000
      s:create_or_age_suggestion("test", 5, "sprite", "high", false, {"action"})
      s:age_out_suggestion("test")
      assert.are.equal("aging", s:get_suggestions()["test"].urgency)
      assert.are.equal(1000, s:get_suggestions()["test"].age_start_tick)
    end)

    it("clears suggestion after aging interval expires", function()
      local s = Suggestions.new()
      s._current_tick = 1000
      s:create_or_age_suggestion("test", 5, "sprite", "high", false, {"action"})
      -- Start aging
      s:age_out_suggestion("test")
      -- Advance past the aging interval (5 minutes = 5*60*60 = 18000 ticks)
      s._current_tick = 1000 + 18001
      s:age_out_suggestion("test")
      assert.is_nil(s:get_suggestions()["test"])
    end)

    it("does nothing for non-existent suggestion", function()
      local s = Suggestions.new()
      assert.has_no.errors(function() s:age_out_suggestion("nope") end)
    end)
  end)

  describe("clear_suggestion()", function()
    it("removes a specific suggestion", function()
      local s = Suggestions.new()
      s:create_or_age_suggestion("a", 1, "s", "low", false, {"x"})
      s:create_or_age_suggestion("b", 2, "s", "low", false, {"y"})
      s:clear_suggestion("a")
      assert.is_nil(s:get_suggestions()["a"])
      assert.is_not_nil(s:get_suggestions()["b"])
    end)
  end)

  describe("clear_suggestions()", function()
    it("resets all state", function()
      local s = Suggestions.new()
      s:create_or_age_suggestion("x", 1, "s", "low", false, {"a"})
      s:remember("x", 42)
      s:clear_suggestions()
      assert.are.equal(0, s:get_current_count())
    end)
  end)

  describe("cached data", function()
    it("stores and retrieves cached lists", function()
      local s = Suggestions.new()
      local list = {{ id = 1 }, { id = 2 }}
      s:set_cached_list("test-key", list)
      assert.are.same(list, s:get_cached_list("test-key"))
    end)

    it("returns nil for unset cache", function()
      local s = Suggestions.new()
      assert.is_nil(s:get_cached_list("nonexistent"))
    end)
  end)

  describe("is_aging()", function()
    it("returns true for aging suggestions", function()
      local s = Suggestions.new()
      s._current_tick = 100
      s:create_or_age_suggestion("k", 5, "s", "high", false, {"a"})
      s:age_out_suggestion("k")
      assert.is_true(s:is_aging("k"))
    end)

    it("returns false for active suggestions", function()
      local s = Suggestions.new()
      s:create_or_age_suggestion("k", 5, "s", "high", false, {"a"})
      assert.is_false(s:is_aging("k"))
    end)
  end)
end)
