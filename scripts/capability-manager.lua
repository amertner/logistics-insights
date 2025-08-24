--- Unified capability manager: centralizes pause state, dependencies, dirty flags, intervals
local capability_manager = {}

---@class CapabilityRecord
---@field reasons table<string, boolean> Active blocking reasons (user, setting, hidden, no_network, dep, other)
---@field deps string[] Dependency capability names
---@field last_run uint Last tick run (for interval gating)
---@field interval uint Base interval override (0 = use scheduler task interval)
---@field dirty boolean Dirty flag (consumption semantics defined by task)
---@field just_updated boolean Transient flag set after a task consumes dirty & runs (cleared next tick)

-- Static registry of capability dependency graph (order-independent)
local registry = {
  window       = { deps = {} },
  delivery     = { deps = {  } },
  activity     = { deps = {  } },
  history      = { deps = { "delivery" } },
  suggestions  = { deps = { "delivery", "activity" } },
  undersupply  = { deps = { "delivery" } },
}

-- Reason precedence order for deriving a single state label
local reason_priority = {
  "user", "setting", "hidden", "no_network", "dep", "other"
}

-- Derive a simple state label from reasons+dependencies
--- Derive a UI/state label for a capability
--- @param player_table PlayerData
--- @param name string Capability name
--- @param rec CapabilityRecord Capability record
--- @param cache table<string, boolean> Memoization cache for recursion
--- @return string state One of: running|user-paused|setting-paused|hidden-paused|no_network-paused|dep-paused|other-paused
local function derive_state(player_table, name, rec, cache, state_cache)
  -- First consider this capability's own reasons with priority (user, setting, hidden, ...)
  for _, r in pairs(reason_priority) do
    if rec.reasons[r] then
      return r .. "-paused" -- e.g. user-pause, setting-paused, hidden-paused
    end
  end
  -- Otherwise, if a dependency is inactive, propagate its reason
  for _, dep in pairs(rec.deps) do
    if not capability_manager.is_active(player_table, dep, cache) then
      -- The capability we depend on is not active
      if dep == "window" then
        return "hidden-paused" -- Special case: if window is hidden, we show hidden state
      end
      -- Simply say a dependency is paused
      return "dep-paused"
    end
  end
  return "running"
end

-- Ensure per-player capabilities table exists and seeded
--- Initialise per-player capability records if missing
--- @param player_table PlayerData
function capability_manager.init_player(player_table)
  player_table.capabilities = player_table.capabilities or {}
  for name, meta in pairs(registry) do
    local rec = player_table.capabilities[name]
    if not rec then
      rec = { reasons = {}, deps = meta.deps, last_run = game.tick, interval = 0, dirty = false, just_updated = false }
      player_table.capabilities[name] = rec
    else
      rec.deps = meta.deps
      rec.reasons = rec.reasons or {}
      if rec.last_run == nil then
        rec.last_run = game.tick
      end
      if rec.interval == nil then
        rec.interval = 0
      end
      if rec.dirty == nil then
        rec.dirty = false
      end
    end
  end
end

-- Internal: check if blocked by any reason
local function reasons_blocking(rec)
  for _, active in pairs(rec.reasons) do
    if active then
      return true
    end
  end
  return false
end

--- Check if a capability is currently active (no blocking reasons and all dependencies active)
--- @param player_table PlayerData
--- @param name string Capability name
--- @param cache table<string, boolean>|nil Optional memo cache
--- @return boolean active True if capability can run
function capability_manager.is_active(player_table, name, cache)
  local caps = player_table.capabilities
  if not caps then
    return true -- No capabilities means nothing is paused
  end
  cache = cache or {}
  if cache[name] ~= nil then
    return cache[name]
  end
  local rec = caps[name]
  if not rec then
    cache[name] = false
    return false
  end
  if reasons_blocking(rec) then
    cache[name] = false
    return false
  end
  for _, dep in ipairs(rec.deps) do
    if not capability_manager.is_active(player_table, dep, cache) then
      cache[name] = false
      return false
    end
  end
  cache[name] = true
  return true
end

--- Set or clear a blocking reason for a capability
--- @param player_table PlayerData
--- @param name string Capability name
--- @param reason string One of: user|setting|hidden|no_network|dep|other
--- @param active boolean If true, add reason; if false, clear it
function capability_manager.set_reason(player_table, name, reason, active)
  local rec = player_table.capabilities and player_table.capabilities[name]
  if not rec then
    return
  end
  if active then
    rec.reasons[reason] = true
  else
    rec.reasons[reason] = nil
  end
end

--- Mark a capability as dirty (work pending)
--- @param player_table PlayerData
--- @param name string Capability name
function capability_manager.mark_dirty(player_table, name)
  local rec = player_table.capabilities and player_table.capabilities[name]
  if rec then
    rec.dirty = true
  end
end

--- Consume (clear) the dirty flag if set
--- @param player_table PlayerData
--- @param name string Capability name
--- @return boolean was_dirty True if it was dirty and is now cleared
function capability_manager.consume_dirty(player_table, name)
  local rec = player_table.capabilities and player_table.capabilities[name]
  if rec and rec.dirty then
    rec.dirty = false
    rec.just_updated = true
    return true
  end
  return false
end

--- Clear transient just_updated flags (call once per tick if needed by UI)
--- @param player_table PlayerData
function capability_manager.clear_just_updated(player_table)
  if not player_table.capabilities then
    return
  end
  for _, rec in pairs(player_table.capabilities) do
    rec.just_updated = false
  end
end

--- Determine whether a per-player task for a capability should run this tick
--- (Also updates last_run when returning true.)
--- @param player_table PlayerData
--- @param name string Capability name
--- @param tick uint Current game tick
--- @param base_interval uint Base scheduler interval for the task
--- @return boolean run_now True if task should execute
--- @return uint elapsed Ticks elapsed since last execution
function capability_manager.should_run(player_table, name, tick, base_interval)
  local rec = player_table.capabilities and player_table.capabilities[name]
  if not rec then
    return false, 0
  end
  if not capability_manager.is_active(player_table, name) then
    return false, tick - (rec.last_run or tick)
  end
  local interval = (rec.interval and rec.interval > 0) and rec.interval or base_interval
  local last = rec.last_run or 0
  local elapsed = tick - last
  if elapsed >= interval then
    rec.last_run = tick
    return true, elapsed
  end
  return false, elapsed
end

--- Build UI state object for a capability
--- @param player_table PlayerData
--- @param name string Capability name
--- @return {name:string,state:string,active:boolean,dirty:boolean,reasons:table<string,boolean>,deps:string[],just_updated:boolean} state Table for UI consumption
function capability_manager.get_ui_state(player_table, name)
  local rec = player_table.capabilities and player_table.capabilities[name]
  if not rec then
    return { name = name, state = "unknown", active = false, dirty = false, reasons = {}, deps = {}, just_updated = false }
  end
  local state = derive_state(player_table, name, rec, {}, {})
  return {
    name = name,
    state = state,
    active = (state == "running"),
    dirty = rec.dirty,
    reasons = rec.reasons,
    deps = rec.deps,
    just_updated = rec.just_updated,
  }
end

--- Snapshot all capability UI states for a player
--- @param player_table PlayerData
--- @return table<string, {name:string,state:string,active:boolean,dirty:boolean,reasons:table<string,boolean>,deps:string[],just_updated:boolean}> snapshot
function capability_manager.snapshot(player_table)
  local snap = {}
  if player_table.capabilities then
    for name in pairs(player_table.capabilities) do
      snap[name] = capability_manager.get_ui_state(player_table, name)
    end
  end
  return snap
end

return capability_manager
