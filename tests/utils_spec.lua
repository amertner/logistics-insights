local mock = require("tests.mocks.factorio")

describe("utils", function()
  local utils

  before_each(function()
    mock.fresh()
    utils = require("scripts.utils")
  end)

  describe("starts_with()", function()
    it("returns true when string starts with prefix", function()
      assert.is_true(utils.starts_with("hello world", "hello"))
    end)

    it("returns false when string does not start with prefix", function()
      assert.is_false(utils.starts_with("hello world", "world"))
    end)

    it("returns true for empty prefix", function()
      assert.is_true(utils.starts_with("anything", ""))
    end)

    it("returns false when prefix is longer than string", function()
      assert.is_false(utils.starts_with("hi", "hello"))
    end)
  end)

  describe("accumulate_quality()", function()
    it("initialises a new key to the count", function()
      local t = {}
      utils.accumulate_quality(t, "normal", 5)
      assert.are.equal(5, t["normal"])
    end)

    it("adds to an existing key", function()
      local t = { normal = 3 }
      utils.accumulate_quality(t, "normal", 7)
      assert.are.equal(10, t["normal"])
    end)

    it("tracks multiple qualities independently", function()
      local t = {}
      utils.accumulate_quality(t, "normal", 2)
      utils.accumulate_quality(t, "uncommon", 5)
      utils.accumulate_quality(t, "normal", 3)
      assert.are.equal(5, t["normal"])
      assert.are.equal(5, t["uncommon"])
    end)
  end)

  describe("table_clear()", function()
    it("removes all keys from a table", function()
      local t = { a = 1, b = 2, c = 3 }
      utils.table_clear(t)
      assert.are.equal(0, _G.table_size(t))
    end)

    it("handles nil gracefully", function()
      assert.has_no.errors(function() utils.table_clear(nil) end)
    end)

    it("handles empty table", function()
      local t = {}
      utils.table_clear(t)
      assert.are.equal(0, _G.table_size(t))
    end)
  end)

  describe("get_item_quality_key()", function()
    it("returns item:quality format", function()
      assert.are.equal("iron-plate:normal", utils.get_item_quality_key("iron-plate", "normal"))
    end)

    it("caches and returns the same string object", function()
      local k1 = utils.get_item_quality_key("copper-wire", "uncommon")
      local k2 = utils.get_item_quality_key("copper-wire", "uncommon")
      assert.are.equal(k1, k2)
    end)
  end)

  describe("get_ItemQuality_key()", function()
    it("delegates to get_item_quality_key", function()
      local iq = { name = "steel-plate", quality = "rare" }
      assert.are.equal("steel-plate:rare", utils.get_ItemQuality_key(iq))
    end)
  end)

  describe("get_valid_sprite_path()", function()
    it("returns the sprite path when valid", function()
      _G.helpers.is_valid_sprite_path = function() return true end
      assert.are.equal("item/iron-plate", utils.get_valid_sprite_path("item/", "iron-plate"))
    end)

    it("returns fallback when primary is invalid", function()
      _G.helpers.is_valid_sprite_path = function(path)
        return path == "entity/assembling-machine-1"
      end
      assert.are.equal(
        "entity/assembling-machine-1",
        utils.get_valid_sprite_path("item/", "ghost-thing", "entity/assembling-machine-1")
      )
    end)

    it("returns empty string when nothing is valid", function()
      _G.helpers.is_valid_sprite_path = function() return false end
      assert.are.equal("", utils.get_valid_sprite_path("item/", "nonexistent"))
    end)
  end)

  describe("get_localised_names()", function()
    it("returns localised names from item prototypes", function()
      _G.prototypes.item["iron-plate"] = { localised_name = "Iron plate" }
      _G.prototypes.quality["normal"] = { localised_name = "Normal" }
      local result = utils.get_localised_names({ item_name = "iron-plate", quality_name = "normal" })
      assert.are.equal("Iron plate", result.iname)
      assert.are.equal("Normal", result.qname)
    end)

    it("falls back to entity prototypes", function()
      _G.prototypes.entity["roboport"] = { localised_name = "Roboport" }
      _G.prototypes.quality["normal"] = { localised_name = "Normal" }
      local result = utils.get_localised_names({ item_name = "roboport", quality_name = "normal" })
      assert.are.equal("Roboport", result.iname)
    end)

    it("uses raw name when no prototype exists", function()
      _G.prototypes.quality["normal"] = { localised_name = "Normal" }
      local result = utils.get_localised_names({ item_name = "unknown-thing", quality_name = "normal" })
      assert.are.equal("unknown-thing", result.iname)
    end)
  end)
end)
