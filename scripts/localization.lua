-- localization.lua - Caching system for localized strings
local localization = {}

-- Cache tables for different types of localizations
local quality_name_cache = {}
local item_name_cache = {}
local quality_item_cache = {}

-- Function to initialize the quality name cache with all available qualities
local function initialize_quality_name_cache()
  -- Clear any existing cache
  quality_name_cache = {}

  -- Try to get qualities from the prototypes API if available
  if script and script.active_mods and prototypes and prototypes.quality then
    for quality_name, _ in pairs(prototypes.quality) do
      quality_name_cache[quality_name] = {"quality-name." .. quality_name}
    end
  else
    -- Fallback to standard qualities if prototypes API is not available
    local standard_qualities = {"normal", "uncommon", "rare", "epic", "legendary"}
    for _, quality in ipairs(standard_qualities) do
      quality_name_cache[quality] = {"quality-name." .. quality}
    end
  end

  -- Always ensure "normal" is available as the default
  if not quality_name_cache["normal"] then
    quality_name_cache["normal"] = {"quality-name.normal"}
  end

  return true
end

-- Get a localized quality name from the cache
function localization.get_quality_name(quality_name)
  -- Validate input
  quality_name = quality_name or "normal"

  -- Initialize cache if it's empty
  if table_size(quality_name_cache) == 0 then
    initialize_quality_name_cache()
  end

  -- Return cached value or create new one
  return quality_name_cache[quality_name] or {"quality-name." .. quality_name}
end

-- Get a localized item name from the cache
function localization.get_item_name(item_name)
  -- Validate input
  if not item_name then
    return {""}
  end

  -- Use cache or create new entry
  if not item_name_cache[item_name] then
    item_name_cache[item_name] = {"item-name." .. item_name}
  end

  return item_name_cache[item_name]
end

-- Get a localized quality+item combined string
function localization.get_quality_item(quality_name, item_name)
  -- Validate inputs
  quality_name = quality_name or "normal"
  if not item_name then
    return {""}
  end

  local cache_key = quality_name .. ":" .. item_name

  if not quality_item_cache[cache_key] then
    -- Different languages use different word ordering, so we use a
    -- dedicated localization key that can be translated appropriately
    quality_item_cache[cache_key] = {
      "quality-item-format.quality-item-format",
      localization.get_quality_name(quality_name),
      localization.get_item_name(item_name)
    }
  end

  return quality_item_cache[cache_key]
end

-- Clear all caches (call this if locale changes)
function localization.clear_caches()
  quality_name_cache = {}
  item_name_cache = {}
  quality_item_cache = {}
end

-- Initialize when game is ready
local function on_init()
  initialize_quality_name_cache()
end

local function on_configuration_changed()
  -- Clear caches on mod or game configuration changes
  localization.clear_caches()
  initialize_quality_name_cache()
end

-- Also initialize on mods loaded, which ensures prototypes are available
local function on_load()
  initialize_quality_name_cache()
end

script.on_init(on_init)
script.on_load(on_load)
script.on_configuration_changed(on_configuration_changed)

-- Return the module
return localization
