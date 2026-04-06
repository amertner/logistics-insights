--- Factorio API mocks for unit testing outside the game engine.
--- Loaded as a Busted helper (runs before every spec file).

local M = {}

-- Polyfill for Factorio's built-in table_size (not in standard Lua)
local function _table_size(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

--- Reset all Factorio globals to a clean default state.
--- Call this in before_each() to isolate tests.
function M.reset()
  -- Persistent game state
  _G.storage = {}

  -- Game runtime
  _G.game = { tick = 0 }

  -- Enum tables used by the codebase
  _G.defines = {
    inventory = { chest = 1 },
    entity_status = { disabled_by_control_behavior = "disabled_by_control_behavior" },
    logistic_member_index = { logistic_container = 1 },
    robot_order_type = {
      deliver = 1,
      pickup = 2,
      construct = 3,
      deconstruct = 4,
      repair = 5,
    },
  }

  -- Mod settings (global-data.lua reads these)
  _G.settings = {
    global = {
      ["li-chunk-processing-interval-ticks"]           = { value = 7 },
      ["li-background-refresh-interval"]               = { value = 10 },
      ["li-chunk-size-global"]                         = { value = 400 },
      ["li-gather-quality-data-global"]                = { value = true },
      ["li-calculate-undersupply"]                     = { value = true },
      ["li-show-all-networks"]                         = { value = true },
      ["li-ignore-player-demands-in-undersupply"]      = { value = false },
      ["li-freeze-highlighting-bots"]                  = { value = false },
      ["li-age-out-suggestions-interval-minutes"]      = { value = 0 },
    },
  }

  -- Helper utilities
  _G.helpers = {
    is_valid_sprite_path = function() return true end,
  }

  -- Prototype lookup tables
  _G.prototypes = {
    item = {},
    quality = {},
    entity = {},
  }

  -- Metatable registration (no-op outside Factorio)
  _G.script = {
    register_metatable = function() end,
  }

  -- Logging (no-op by default; tests can replace to capture)
  _G.log = function() end

  -- Factorio built-in
  _G.table_size = _table_size
end

--- Flush all cached modules under the given prefixes from package.loaded
--- so the next require() picks up fresh globals.
function M.unload(...)
  local prefixes = { ... }
  for mod_name, _ in pairs(package.loaded) do
    for _, prefix in ipairs(prefixes) do
      if mod_name:sub(1, #prefix) == prefix then
        package.loaded[mod_name] = nil
      end
    end
  end
end

--- Convenience: reset globals and unload all project modules.
function M.fresh()
  M.reset()
  M.unload("scripts.")
end

-- Run once when Busted loads this helper so the very first require() of
-- any project module sees the globals.
M.reset()

return M
