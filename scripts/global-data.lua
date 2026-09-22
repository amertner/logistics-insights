--- Manage and cache global settings

local global_data = {}

function global_data.init()
  storage.global = storage.global or {}
  global_data.settings_changed() -- Cache current settings

  -- Current player network being refreshed
  storage.fg_refreshing_network_id = nil ---@type number|nil
  -- Current network being refreshed in the background
  storage.bg_refreshing_network_id = nil ---@type number|nil
end

-- The defaults declared in settings.lua, in one place. A setting always exists, so these are only
-- read if storage.global is somehow missing a field, but keeping them here means the two never drift
local DEFAULTS = {
  chunk_interval_ticks = 7,
  background_refresh_interval_secs = 30,
  chunk_size = 400,
  undersupply_rolling_divisor = 3,
  analysis_chunk_divisor = 4,
  gather_quality_data = true,
  calculate_undersupply = true,
  show_all_networks = true,
  ignore_player_demands_in_undersupply = true,
  freeze_highlighting_bots = true,
  age_out_suggestions_interval_minutes = 3,
  long_trip_min_distance = 200,
  long_trip_sensitivity = "normal",
  ignore_mobile_trips = true,
}

---@param key string A field of storage.global
---@return any The cached value, or its default if the field is missing
local function cached(key)
  -- storage.global itself can be missing: on_load runs before on_configuration_changed, so a save
  -- from a version that predates the cache has no table yet. Fall back to the defaults until then
  local g = storage.global
  local value = g and g[key]
  if value == nil then return DEFAULTS[key] end
  return value
end

-- Called when global settings change so we can cache them and take necessary action
function global_data.settings_changed()
  local g = storage.global
  local sg = settings.global
  g.chunk_interval_ticks = tonumber(sg["li-chunk-processing-interval-ticks"].value) or DEFAULTS.chunk_interval_ticks
  g.background_refresh_interval_secs = tonumber(sg["li-background-refresh-interval"].value) or DEFAULTS.background_refresh_interval_secs
  g.background_refresh_interval_ticks = g.background_refresh_interval_secs * 60
  g.chunk_size = tonumber(sg["li-chunk-size-global"].value) or DEFAULTS.chunk_size
  g.undersupply_rolling_divisor = tonumber(sg["li-undersupply-rolling-divisor"].value) or DEFAULTS.undersupply_rolling_divisor
  g.analysis_chunk_divisor = tonumber(sg["li-analysis-chunk-divisor"].value) or DEFAULTS.analysis_chunk_divisor
  g.gather_quality_data = sg["li-gather-quality-data-global"].value ~= false
  g.calculate_undersupply = sg["li-calculate-undersupply"].value ~= false
  g.show_all_networks = sg["li-show-all-networks"].value ~= false
  g.ignore_player_demands_in_undersupply = sg["li-ignore-player-demands-in-undersupply"].value ~= false
  g.freeze_highlighting_bots = sg["li-freeze-highlighting-bots"].value ~= false
  g.age_out_suggestions_interval_minutes = tonumber(sg["li-age-out-suggestions-interval-minutes"].value) or DEFAULTS.age_out_suggestions_interval_minutes
  g.long_trip_min_distance = tonumber(sg["li-long-trip-min-distance"].value) or DEFAULTS.long_trip_min_distance
  g.long_trip_sensitivity = sg["li-long-trip-suggestions"].value or DEFAULTS.long_trip_sensitivity
  g.ignore_mobile_trips = sg["li-ignore-mobile-trips"].value ~= false
end

---@return integer How often a chunk of bots is counted, in ticks (the "Ticks between chunks" setting)
function global_data.chunk_interval_ticks()
  return cached("chunk_interval_ticks")
end

---@return integer The refresh interval for background network scanning, seconds
function global_data.background_refresh_interval_secs()
  return cached("background_refresh_interval_secs")
end

---@return integer The refresh interval for background network scanning, ticks
function global_data.background_refresh_interval_ticks()
  local g = storage.global
  return (g and g.background_refresh_interval_ticks) or DEFAULTS.background_refresh_interval_secs * 60
end

---@return integer The global chunk size setting
function global_data.chunk_size()
  return cached("chunk_size")
end

---@return integer The rolling-divisor for undersupply per-requester sampling (1 = disabled, sample everyone every sweep)
function global_data.undersupply_rolling_divisor()
  return cached("undersupply_rolling_divisor")
end

-- Divisor applied to the chunk size for scanning bots and cells. Fixed at 1: scans are cheap
-- per entity, and a single pass gives a coherent snapshot, so they get the full chunk. Only the
-- analysis phase has a divisor setting, below
global_data.CHUNK_DIVISOR = 1

---@return integer Divisor for analysis-phase chunk size (undersupply + storage). Scanning uses CHUNK_DIVISOR instead.
function global_data.analysis_chunk_divisor()
  return cached("analysis_chunk_divisor")
end

---@return boolean True if quality data gathering is enabled
function global_data.gather_quality_data()
  return cached("gather_quality_data")
end

---@return boolean True if undersupply calculation is enabled
function global_data.calculate_undersupply()
  return cached("calculate_undersupply")
end

---@return boolean True if all networks should be shown
function global_data.show_all_networks()
  return cached("show_all_networks")
end

---@return boolean True if non-player networks should be purged
function global_data.purge_nonplayer_networks()
  return not global_data.show_all_networks()
end

function global_data.background_scans_disabled()
  -- Background scans are disabled if the refresh interval is zero
  return global_data.background_refresh_interval_ticks() == 0
end

function global_data.background_scans_enabled()
  -- Background scans are enabled if the refresh interval is greater than zero
  return global_data.background_refresh_interval_ticks() > 0
end

function global_data.ignore_player_demands_in_undersupply()
  -- Player logistic requests are left out of undersupply demand unless the setting is disabled
  return cached("ignore_player_demands_in_undersupply")
end

function global_data.freeze_highlighting_bots()
  return cached("freeze_highlighting_bots")
end

function global_data.age_out_suggestions_interval_minutes()
  return cached("age_out_suggestions_interval_minutes")
end

function global_data.age_out_suggestions_interval_ticks()
  return global_data.age_out_suggestions_interval_minutes() * 60 * 60
end

-- What each sensitivity counts as "much further than usual", as a multiple of an item's typical
-- trip. "off" is deliberately absent, so it reads as no factor at all
local LONG_TRIP_MEDIAN_FACTORS = { relaxed = 8, normal = 4, sensitive = 2 }

---@return integer The shortest trip that can be suggested as unusually long, in tiles
function global_data.long_trip_min_distance()
  return cached("long_trip_min_distance")
end

---@return number|nil factor Multiple of an item's median trip, or nil if the suggestion is off
function global_data.long_trip_median_factor()
  return LONG_TRIP_MEDIAN_FACTORS[cached("long_trip_sensitivity")]
end

---@return boolean True to leave trips to or from a character or spidertron out of the Longest trip list
function global_data.ignore_mobile_trips()
  return cached("ignore_mobile_trips")
end

return global_data