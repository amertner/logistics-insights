--- Manage and cache global settings

local global_data = {}

function global_data.init()
  storage.global = storage.global or {}
  global_data.settings_changed() -- Cache current settings

  -- Current network being refreshed in the background
  storage.bg_refreshing_network_id = nil ---@type number|nil
end

-- Called when global settings change so we can cache them and take necessary action
function global_data.settings_changed()
  storage.global.chunk_interval_ticks = tonumber(settings.global["li-chunk-processing-interval-ticks"].value) or 7
  storage.global.background_refresh_interval_secs = tonumber(settings.global["li-background-refresh-interval"].value) or 10
  storage.global.chunk_size = tonumber(settings.global["li-chunk-size-global"]) or 400
  storage.global.gather_quality_data = settings.global["li-gather-quality-data-global"].value ~= false
  storage.global.show_all_networks = settings.global["li-show-all-networks"].value ~= false
end

---@return integer The global bot chunk interval setting
function global_data.chunk_interval_ticks()
  return storage.global.chunk_interval_ticks or 7
end

---@return integer The refresh interval for background network scanning, seconds
function global_data.background_refresh_interval_secs()
  return storage.global.background_refresh_interval_secs or 11
end

---@return integer The refresh interval for background network scanning, ticks
function global_data.background_refresh_interval_ticks()
  return global_data.background_refresh_interval_secs() * 60
end

---@return integer The global chunk size setting
function global_data.chunk_size()
  return storage.global.chunk_size or 400
end

---@return boolean True if quality data gathering is enabled
function global_data.gather_quality_data()
  return storage.global.gather_quality_data
end

---@return boolean True if all networks should be shown
function global_data.show_all_networks()
  return storage.global.show_all_networks
end

---@return boolean True if non-player networks should be purged
function global_data.purge_nonplayer_networks()
  return not storage.global.show_all_networks
end

return global_data