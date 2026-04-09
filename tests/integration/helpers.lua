--- Integration test helpers for factorio-test
--- Provides NetworkBuilder for creating logistics networks and utility functions

local helpers = {}

local scheduler = require("scripts.scheduler")
local bot_counter = require("scripts.bot-counter")
local logistic_cell_counter = require("scripts.logistic-cell-counter")
local network_data = require("scripts.network-data")
local analysis_coordinator = require("scripts.analysis-coordinator")

-- Whether Space Age (quality system) is available
helpers.has_quality = script.active_mods["space-age"] ~= nil

-------------------------------------------------------------------------------
-- NetworkBuilder: fluent API for creating powered logistics networks
-------------------------------------------------------------------------------

---@class NetworkBuilder
---@field _surface LuaSurface
---@field _origin MapPosition
---@field _force string
---@field _roboports table[]
---@field _providers table[]
---@field _requesters table[]
---@field _storages table[]
---@field _buffers table[]
---@field _entities LuaEntity[]
local NetworkBuilder = {}
NetworkBuilder.__index = NetworkBuilder

--- Create a new NetworkBuilder
---@param surface LuaSurface The surface to build on
---@param origin MapPosition Centre point for the network {x, y}
---@param force? string Force name, defaults to "player"
---@return NetworkBuilder
function NetworkBuilder.new(surface, origin, force)
  local self = setmetatable({}, NetworkBuilder)
  self._surface = surface
  self._origin = {x = origin[1] or origin.x or 0, y = origin[2] or origin.y or 0}
  self._force = force or "player"
  self._roboports = {}
  self._providers = {}
  self._requesters = {}
  self._storages = {}
  self._buffers = {}
  self._entities = {}
  return self
end

--- Resolve an offset relative to the builder's origin
---@param offset number[] {dx, dy}
---@return MapPosition
function NetworkBuilder:_pos(offset)
  return {
    x = self._origin.x + (offset[1] or offset.x or 0),
    y = self._origin.y + (offset[2] or offset.y or 0),
  }
end

--- Place an entity and track it
---@param params table create_entity params
---@return LuaEntity
function NetworkBuilder:_place(params)
  params.force = params.force or self._force
  local entity = self._surface.create_entity(params)
  assert(entity, "Failed to create entity: " .. params.name .. " at " .. serpent.line(params.position))
  table.insert(self._entities, entity)
  return entity
end

--- Add a roboport to the network
---@param offset number[] Position offset from origin {dx, dy}
---@param opts? {bots?: number, construction_bots?: number, quality?: string}
---@return NetworkBuilder self (for chaining)
function NetworkBuilder:add_roboport(offset, opts)
  table.insert(self._roboports, {offset = offset, opts = opts or {}})
  return self
end

--- Add a passive-provider chest with items
---@param offset number[] Position offset from origin {dx, dy}
---@param items table[] Array of {name, count} or {name, count, quality}
---@param opts? {type?: string, quality?: string}
---@return NetworkBuilder self
function NetworkBuilder:add_provider(offset, items, opts)
  opts = opts or {}
  table.insert(self._providers, {
    offset = offset,
    items = items,
    chest_type = opts.type or "passive-provider-chest",
    quality = opts.quality,
  })
  return self
end

--- Add a requester chest with request filters
---@param offset number[] Position offset from origin {dx, dy}
---@param requests table[] Array of {name, count} or {name, count, quality}
---@param opts? {quality?: string}
---@return NetworkBuilder self
function NetworkBuilder:add_requester(offset, requests, opts)
  opts = opts or {}
  table.insert(self._requesters, {offset = offset, requests = requests, quality = opts.quality})
  return self
end

--- Add a storage chest, optionally pre-filled
---@param offset number[] Position offset from origin {dx, dy}
---@param items? table[] Array of {name, count} or {name, count, quality}
---@param opts? {quality?: string, filter?: ItemFilter}
---@return NetworkBuilder self
function NetworkBuilder:add_storage(offset, items, opts)
  opts = opts or {}
  table.insert(self._storages, {offset = offset, items = items or {}, quality = opts.quality, filter = opts.filter})
  return self
end

--- Add a buffer chest, optionally pre-filled
---@param offset number[] Position offset from origin {dx, dy}
---@param items? table[] Array of {name, count} or {name, count, quality}
---@param opts? {quality?: string}
---@return NetworkBuilder self
function NetworkBuilder:add_buffer(offset, items, opts)
  opts = opts or {}
  table.insert(self._buffers, {offset = offset, items = items or {}, quality = opts.quality})
  return self
end

--- Insert items into an entity's chest inventory
---@param entity LuaEntity
---@param items table[] Array of {name, count} or {name, count, quality}
local function insert_items(entity, items)
  local inv = entity.get_inventory(defines.inventory.chest)
  if not inv then return end
  for _, item in ipairs(items) do
    local stack = {name = item[1], count = item[2]}
    if item[3] then stack.quality = item[3] end
    inv.insert(stack)
  end
end

--- Set request filters on a requester/buffer chest via logistic sections API
---@param entity LuaEntity
---@param requests table[] Array of {name, count} or {name, count, quality}
local function set_request_filters(entity, requests)
  local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
  if not point then return end
  local section = point.get_section(1)
  if not section then return end
  for i, req in ipairs(requests) do
    section.set_slot(i, {
      value = {
        type = "item",
        name = req[1],
        quality = req[3] or "normal",
      },
      min = req[2],
    })
  end
end

--- Build all entities and return them along with the network reference.
--- Must be called inside an async test; waits 2 ticks for network formation.
---@return {entities: LuaEntity[], roboports: LuaEntity[], network: LuaLogisticNetwork|nil}
function NetworkBuilder:build()
  -- 1. Power: electric-energy-interface + substation at origin
  self:_place({
    name = "electric-energy-interface",
    position = self:_pos({-3, -3}),
  })
  self:_place({
    name = "substation",
    position = self:_pos({0, -3}),
  })

  -- 2. Roboports
  local roboports = {}
  for _, rp in ipairs(self._roboports) do
    local params = {
      name = "roboport",
      position = self:_pos(rp.offset),
    }
    if rp.opts.quality and helpers.has_quality then
      params.quality = rp.opts.quality
    end
    local entity = self:_place(params)
    table.insert(roboports, entity)

    -- Insert logistic robots
    local bot_count = rp.opts.bots or 0
    if bot_count > 0 then
      entity.insert({name = "logistic-robot", count = bot_count})
    end
    -- Insert construction robots
    local cbots = rp.opts.construction_bots or 0
    if cbots > 0 then
      entity.insert({name = "construction-robot", count = cbots})
    end
  end

  -- 3. Provider chests
  for _, prov in ipairs(self._providers) do
    local params = {
      name = prov.chest_type,
      position = self:_pos(prov.offset),
    }
    if prov.quality and helpers.has_quality then
      params.quality = prov.quality
    end
    local entity = self:_place(params)
    insert_items(entity, prov.items)
  end

  -- 4. Requester chests
  for _, req in ipairs(self._requesters) do
    local params = {
      name = "requester-chest",
      position = self:_pos(req.offset),
    }
    if req.quality and helpers.has_quality then
      params.quality = req.quality
    end
    local entity = self:_place(params)
    set_request_filters(entity, req.requests)
  end

  -- 5. Storage chests
  for _, stor in ipairs(self._storages) do
    local params = {
      name = "storage-chest",
      position = self:_pos(stor.offset),
    }
    if stor.quality and helpers.has_quality then
      params.quality = stor.quality
    end
    local entity = self:_place(params)
    if stor.filter then
      entity.set_filter(1, stor.filter)
    end
    if #stor.items > 0 then
      insert_items(entity, stor.items)
    end
  end

  -- 6. Buffer chests
  for _, buf in ipairs(self._buffers) do
    local params = {
      name = "buffer-chest",
      position = self:_pos(buf.offset),
    }
    if buf.quality and helpers.has_quality then
      params.quality = buf.quality
    end
    local entity = self:_place(params)
    if #buf.items > 0 then
      insert_items(entity, buf.items)
    end
  end

  -- Find network (may need a tick to form)
  local network = self._surface.find_logistic_network_by_position(self._origin, self._force)

  return {
    entities = self._entities,
    roboports = roboports,
    network = network,
  }
end

--- Destroy all entities created by this builder (for cleanup)
function NetworkBuilder:destroy()
  for _, entity in ipairs(self._entities) do
    if entity.valid then
      entity.destroy()
    end
  end
  self._entities = {}
end

helpers.NetworkBuilder = NetworkBuilder

-------------------------------------------------------------------------------
-- Utility: apply mod settings and refresh global_data cache
-------------------------------------------------------------------------------

--- Apply global settings for the duration of a test.
--- Writes directly to storage.global cache to avoid triggering
--- on_runtime_mod_setting_changed (which expects a player_index).
--- Call in before_each or at the start of a test.
---@param overrides table<string, any> Map of setting name to value
function helpers.apply_settings(overrides)
  -- Setting name -> storage.global cache key mapping
  -- (mirrors global_data.settings_changed())
  local setting_map = {
    ["li-chunk-processing-interval-ticks"] = function(v)
      storage.global.chunk_interval_ticks = tonumber(v) or 7
    end,
    ["li-background-refresh-interval"] = function(v)
      local secs = tonumber(v) or 10
      storage.global.background_refresh_interval_secs = secs
      storage.global.background_refresh_interval_ticks = secs * 60
    end,
    ["li-chunk-size-global"] = function(v)
      storage.global.chunk_size = tonumber(v) or 400
    end,
    ["li-gather-quality-data-global"] = function(v)
      storage.global.gather_quality_data = v ~= false
    end,
    ["li-calculate-undersupply"] = function(v)
      storage.global.calculate_undersupply = v ~= false
    end,
    ["li-show-all-networks"] = function(v)
      storage.global.show_all_networks = v ~= false
    end,
    ["li-ignore-player-demands-in-undersupply"] = function(v)
      storage.global.ignore_player_demands_in_undersupply = v ~= false
    end,
    ["li-freeze-highlighting-bots"] = function(v)
      storage.global.freeze_highlighting_bots = v ~= false
    end,
    ["li-age-out-suggestions-interval-minutes"] = function(v)
      storage.global.age_out_suggestions_interval_minutes = tonumber(v) or 0
    end,
  }

  storage.global = storage.global or {}
  for name, value in pairs(overrides) do
    local setter = setting_map[name]
    if setter then
      setter(value)
    end
  end

  -- Push global-task interval overrides into the scheduler. In production this
  -- happens via control.lua's on_runtime_mod_setting_changed handler; the test
  -- helper bypasses that handler (which expects a player_index), so we have to
  -- do it explicitly. Without this, background-refresh stays locked at whatever
  -- interval apply_global_settings() saw at on_init/on_load time, which defeats
  -- the settings override above.
  scheduler.apply_global_settings()
end

-------------------------------------------------------------------------------
-- Utility: synchronous full-network scan (test-only)
-------------------------------------------------------------------------------

--- Synchronously run a complete bot + cell scan of one network, bypassing
--- the scheduler. Returns when bot_items and cell counts reflect current
--- entity state. Used by tests to get a fresh snapshot at a chosen instant
--- without depending on the production scheduler's cadence (which can alias
--- with bot delivery cycles in tight test scenarios).
---@param network_id number
function helpers.run_full_scan(network_id)
  local nwd = network_data.get_networkdata_fromid(network_id)
  if not nwd then return end
  local network = network_data.get_LuaNetwork(nwd)
  if not network or not network.valid then return end

  -- Tear down any in-flight background scan; we're taking over.
  storage.bg_refreshing_network_id = nil

  -- Initialise both chunkers fresh
  bot_counter.init_background_processing(nwd, network)
  logistic_cell_counter.init_background_processing(nwd, network)

  -- Drive the chunker state machines to completion. The state machine needs
  -- two process_chunk() calls per chunker (fetch → process), so a small
  -- bounded loop suffices for any reasonable test network.
  for _ = 1, 8 do
    if not bot_counter.is_scanning_done(nwd) then
      bot_counter.process_next_chunk(nwd)
    end
    if not logistic_cell_counter.is_scanning_done(nwd) then
      logistic_cell_counter.process_next_chunk(nwd)
    end
    if bot_counter.is_scanning_done(nwd) and logistic_cell_counter.is_scanning_done(nwd) then
      break
    end
  end

  network_data.finished_scanning_network(nwd)
end

--- Synchronously run a complete analysis pass on a network: free suggestions,
--- undersupply, and storage analysis. Tear down any analysis already in flight
--- so this is the only one running. Used by tests after run_full_scan() to get
--- fresh derived data (undersupply lists, suggestions) without waiting for the
--- production analysis-coordinator's gated cadence.
---@param network_id number
function helpers.run_full_analysis(network_id)
  local nwd = network_data.get_networkdata_fromid(network_id)
  if not nwd then return end

  -- Tear down any in-flight analysis; we're taking over.
  analysis_coordinator.stop_analysis()

  analysis_coordinator.start_analysis(nwd)

  -- Drive the analysis state machine to completion. Each step transitions one
  -- substage (free suggestions → undersupply → storage), with the chunkers
  -- inside undersupply/storage needing two calls each (fetch → process). 16
  -- iterations is a safe ceiling for any reasonable test network.
  for _ = 1, 16 do
    if not storage.analysing_networkdata then break end
    analysis_coordinator.run_analysis_step()
  end
end

-------------------------------------------------------------------------------
-- Utility: timing budget instrumentation
-------------------------------------------------------------------------------

--- Record an actual timing value against an expected budget. Always logs
--- "[budget] <label>: actual=N expected<=M (delta=±D)" so a single test run
--- collects every actual value, even from tests that would otherwise fail
--- early. To keep tests progressing through all phases while real floors are
--- being measured, the assertion uses a loose 10x ceiling instead of the
--- documented budget. Once you've read the log and tightened budgets, replace
--- the call sites with plain `assert(actual <= budget, ...)` again.
---@param label string Human-readable phase name (used in log + failure message)
---@param actual number Observed timing in ticks
---@param budget number Documented budget (used only for the log delta + as the basis for the loose ceiling)
function helpers.record_budget(label, actual, budget)
  local delta = actual - budget
  local sign = (delta >= 0) and "+" or ""
  log("[budget] " .. label
    .. ": actual=" .. actual
    .. " expected<=" .. budget
    .. " (delta=" .. sign .. delta .. ")")
  local ceiling = budget * 10 + 200
  assert(actual <= ceiling,
    label .. " catastrophically slow: " .. actual .. " ticks (loose ceiling " .. ceiling .. ", documented budget " .. budget .. ")")
end

-------------------------------------------------------------------------------
-- Utility: wait for LI to discover and analyse a network
-------------------------------------------------------------------------------

--- Poll each tick until LI has completed at least one analysis pass on a network.
--- Use inside an async() test. Calls done() when the condition is met.
---@param network_id number The network ID to wait for
---@param start_tick number The tick at which the test started (to detect new analysis)
---@param timeout_ticks number Maximum ticks to wait
---@param callback fun(networkdata: LINetworkData) Called when analysis completes; should call done()
function helpers.wait_for_analysis(network_id, start_tick, timeout_ticks, callback)
  local deadline = game.tick + timeout_ticks
  local found = false
  on_tick(function()
    if found then return end
    if game.tick > deadline then
      error("Timed out waiting for analysis of network " .. tostring(network_id)
        .. " (waited " .. timeout_ticks .. " ticks)")
    end
    local nwd = storage.networks and storage.networks[network_id]
    if nwd and nwd.last_analysed_tick and nwd.last_analysed_tick > start_tick then
      found = true
      callback(nwd)
      done()
    end
  end)
end

--- Poll until a network ID appears in storage.networks.
--- Does NOT call done() — the callback is responsible for eventually calling done().
---@param origin MapPosition Position to search for network
---@param force string Force name
---@param timeout_ticks number Maximum ticks to wait
---@param callback fun(network_id: number, networkdata: LINetworkData)
function helpers.wait_for_network_discovery(origin, force, timeout_ticks, callback)
  local deadline = game.tick + timeout_ticks
  local found = false
  on_tick(function()
    if found then return end
    if game.tick > deadline then
      error("Timed out waiting for network discovery at " .. serpent.line(origin))
    end
    local surface = game.surfaces[1]
    local network = surface.find_logistic_network_by_position(origin, force)
    if network and network.valid then
      local nwd = storage.networks and storage.networks[network.network_id]
      if nwd then
        found = true
        callback(network.network_id, nwd)
        -- NOTE: no done() here — callback is responsible for calling done()
      end
    end
  end)
end

--- Clear the surface and lay down lab tiles so entities have valid ground.
--- Use this instead of surface.clear(true) directly.
---@param surface LuaSurface
---@param radius? number Tile radius around origin to fill (default 64)
function helpers.clear_surface(surface, radius)
  radius = radius or 64
  surface.clear(true)
  -- Place lab tiles so entities have valid ground to be placed on
  local tiles = {}
  for x = -radius, radius do
    for y = -radius, radius do
      table.insert(tiles, {name = "lab-dark-1", position = {x, y}})
    end
  end
  surface.set_tiles(tiles)
end

--- Teleport player 1 to a position so LI discovers the network there
---@param position MapPosition
function helpers.teleport_player(position)
  local player = game.get_player(1)
  if player and player.valid then
    player.teleport(position, game.surfaces[1])
  end
end

--- Count total values in a quality table (quality_name -> count)
---@param quality_table table<string, number>
---@return number
function helpers.sum_quality_table(quality_table)
  local total = 0
  for _, count in pairs(quality_table or {}) do
    total = total + count
  end
  return total
end

return helpers
