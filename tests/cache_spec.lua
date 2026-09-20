local mock = require("tests.mocks.factorio")

describe("cache", function()
  local cache

  before_each(function()
    mock.fresh()
    cache = require("scripts.cache")
  end)

  describe("new()", function()
    it("creates a cache with default generator", function()
      local c = cache.new()
      -- Default generator returns the key itself
      assert.are.equal("foo", c:get("foo"))
    end)

    it("creates a cache with custom generator", function()
      local c = cache.new(function(key) return key .. "!" end)
      assert.are.equal("bar!", c:get("bar"))
    end)
  end)

  describe("get()", function()
    it("returns nil for nil key", function()
      local c = cache.new()
      assert.is_nil(c:get(nil))
    end)

    it("generates and caches on first access", function()
      local calls = 0
      local c = cache.new(function(key)
        calls = calls + 1
        return string.upper(key)
      end)
      assert.are.equal("ABC", c:get("abc"))
      assert.are.equal("ABC", c:get("abc"))
      assert.are.equal(1, calls) -- generator called only once
    end)

    it("passes extra args to generator", function()
      local c = cache.new(function(key, suffix)
        return key .. (suffix or "")
      end)
      assert.are.equal("foo-bar", c:get("foo", "-bar"))
    end)
  end)

  describe("clear()", function()
    it("forgets every value, so the generator runs again", function()
      local calls = 0
      local c = cache.new(function(key) calls = calls + 1 return key end)
      c:get("a")
      c:get("b")
      c:clear()
      c:get("a")
      assert.are.equal(3, calls)
    end)
  end)
end)
