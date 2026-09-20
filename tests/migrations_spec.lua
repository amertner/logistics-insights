local mock = require("tests.mocks.factorio")

-- The migration runner in scripts/migrations.lua maps a save's old version
-- onto the Factorio 2.0 line with utils.canonical_mod_version() before
-- comparing it with the migration keys. migrations.lua itself pulls in the
-- whole GUI stack, so the mapping lives in utils and is tested here.
describe("canonical_mod_version()", function()
  local utils

  before_each(function()
    mock.fresh()
    utils = require("scripts.utils")
  end)

  it("maps the Factorio 2.1 line onto the 2.0 line, keeping the patch", function()
    assert.equals("1.2.7", utils.canonical_mod_version("1.3.7"))
    assert.equals("1.2.0", utils.canonical_mod_version("1.3.0"))
  end)

  it("leaves the 2.0 line alone", function()
    assert.equals("1.2.7", utils.canonical_mod_version("1.2.7"))
  end)

  it("leaves versions from before the two lines alone", function()
    assert.equals("1.1.3", utils.canonical_mod_version("1.1.3"))
    assert.equals("1.1.1", utils.canonical_mod_version("1.1.1"))
    assert.equals("0.10.12", utils.canonical_mod_version("0.10.12"))
  end)

  it("maps later game versions onto the 2.0 line too", function()
    assert.equals("1.2.2", utils.canonical_mod_version("1.4.2"))
  end)

  it("orders correctly against 2.0-line migration keys", function()
    local cmp = helpers.compare_versions
    -- A 2.1 save on 1.3.4 must run a 1.2.5 key, and one on 1.3.5 must not.
    assert.is_true(cmp(utils.canonical_mod_version("1.3.4"), "1.2.5") < 0)
    assert.is_false(cmp(utils.canonical_mod_version("1.3.5"), "1.2.5") < 0)
    -- Saves from before the split always run the first 1.2.x key.
    assert.is_true(cmp(utils.canonical_mod_version("1.1.3"), "1.2.0") < 0)
  end)
end)
