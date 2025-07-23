-- localization.lua - Caching system for localized strings
local localization = {}

local Cache = require("scripts.cache")

-- Cache tables for different types of localizations
local quality_name_cache = Cache.new(function(quality_name) return {"quality-name." .. quality_name} end)
local item_name_cache = Cache.new(function(item_name) return {"item-name." .. item_name} end)
local quality_item_cache = Cache.new(function(cache_key)
  -- This generator isn't actually used as we handle the compound keys manually
  -- in the get_quality_item function
  return {""}
end)

-- Function to initialize the quality name cache with all available qualities
local function initialize_quality_name_cache()
  -- Clear any existing cache
  quality_name_cache:clear()

  -- Try to get qualities from the prototypes API if available
  if script and script.active_mods and prototypes and prototypes.quality then
    for quality_name, _ in pairs(prototypes.quality) do
      quality_name_cache:set(quality_name, {"quality-name." .. quality_name})
    end
  else
    -- Fallback to standard qualities if prototypes API is not available
    local standard_qualities = {"normal", "uncommon", "rare", "epic", "legendary"}
    for _, quality in ipairs(standard_qualities) do
      quality_name_cache:set(quality, {"quality-name." .. quality})
    end
  end

  -- Always ensure "normal" is available as the default
  if not quality_name_cache:has("normal") then
    quality_name_cache:set("normal", {"quality-name.normal"})
  end

  return true
end

-- Get a localized quality name from the cache
function localization.get_quality_name(quality_name)
  -- Validate input
  quality_name = quality_name or "normal"

  -- Initialize cache if it's empty
  if quality_name_cache:size() == 0 then
    initialize_quality_name_cache()
  end

  -- Return cached value or generate new one
  return quality_name_cache:get(quality_name)
end

-- Get a localized item name from the cache
function localization.get_item_name(item_name)
  -- Validate input
  if not item_name then
    return {""}
  end

  -- Use cache with automatic generation
  return item_name_cache:get(item_name)
end

-- Get a localized quality+item combined string
function localization.get_quality_item(quality_name, item_name)
  -- Validate inputs
  quality_name = quality_name or "normal"
  if not item_name then
    return {""}
  end

  local cache_key = quality_name .. ":" .. item_name
  
  -- The cache generator won't work properly with our compound key
  -- So we handle it manually here
  if not quality_item_cache:has(cache_key) then
    quality_item_cache:set(cache_key, {
      "quality-item-format.quality-item-format",
      localization.get_quality_name(quality_name),
      localization.get_item_name(item_name)
    })
  end

  return quality_item_cache:get(cache_key)
end

-- Clear all caches (call this if locale changes)
function localization.clear_caches()
  quality_name_cache:clear()
  item_name_cache:clear()
  quality_item_cache:clear()
end

-- Initialize when game is ready
function localization.on_init()
  initialize_quality_name_cache()
end

function localization.on_configuration_changed()
  -- Clear caches on mod or game configuration changes
  localization.clear_caches()
  initialize_quality_name_cache()
end

-- Return the module
return localization
