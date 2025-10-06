--- Miscellaneous utility functions for the Logistics Insights mod
--- @alias StringArray string[]
--- @alias AnyArray any[]
local utils = {}

---@alias QualityTable table<string, number> -- Quality name to count mapping

---@class ItemQuality
---@field name string        -- Prototype/item name
---@field quality string     -- Quality ("normal", "uncommon", etc.)

--- Test whether a string starts with the given prefix.
--- @param str string
--- @param prefix string
--- @return boolean starts_with True if the string starts with prefix
function utils.starts_with(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

--- Get a random element from an array-like list (uses math.random).
--- @generic T
--- @param list T[]|nil list Array-like table (sequential integer keys) or nil
--- @return T|nil value Randomly selected element, or nil if list empty/nil
function utils.get_random(list)
  if not list or table_size(list) == 0 then
    return nil
  end
  local index = math.random(1, table_size(list))
  return list[index]
end

--- Increment a quality count; initializes entry to 0 if absent.
--- @param quality_table QualityTable
--- @param quality string
--- @param count number
function utils.accumulate_quality(quality_table, quality, count)
  if not quality_table[quality] then
    quality_table[quality] = 0
  end
  quality_table[quality] = quality_table[quality] + count
end

--- Clear a table in place by removing all keys.
--- @param t table
function utils.table_clear(t)
  if not t then return end
  for k, _ in pairs(t) do
    t[k] = nil
  end
end

-- Create a table to store combined (name/quality) keys for reduced memory fragmentation
--- Cache of combined item+quality keys to reduce temporary allocations.
--- @type table<string, string> cache_key -> interned key (same string value)
local item_quality_keys = {}

--- Return (and cache) a stable key for an item/quality pair ("item:quality").
--- @param item_name string
--- @param quality string
--- @return string key Interned combined key
function utils.get_item_quality_key(item_name, quality)
  local cache_key = item_name .. ":" .. quality
  local key = item_quality_keys[cache_key]
  if not key then
    key = cache_key
    item_quality_keys[cache_key] = key
  end
  return key
end

--- Return (and cache) a stable key for an item/quality pair ("item:quality").
--- @param iq ItemQuality
--- @return string key Interned combined key
function utils.get_ItemQuality_key(iq)
  return utils.get_item_quality_key(iq.name, iq.quality)
end

--- Get the sprite path for a given prefix/item.
--- If the sprite does not exist, returns nil
--- @param prefix string Prefix, e.g. "item/" or "entity/"
--- @param name string Item/entity name
--- @return SpritePath|string sprite_path Full sprite path, e.g. "item/iron-plate
function utils.get_valid_sprite_path(prefix, name)
  local entity_sprite = prefix .. name  ---@type SpritePath
  if helpers.is_valid_sprite_path(entity_sprite) then
    return entity_sprite
  end
  -- Could add logic here to try different prefixes

  return ""
end

-- Get the localised item and quality names
---@param entry DeliveryItem|DeliveredItems|UndersupplyItem
---@return { iname: LocalisedString, qname: LocalisedString }
function utils.get_localised_names(entry)
  if entry.item_name and entry.quality_name then
    if prototypes.item[entry.item_name] then
      localised_name = prototypes.item[entry.item_name].localised_name
    elseif prototypes.entity[entry.item_name] then
      localised_name = prototypes.entity[entry.item_name].localised_name
    end
    localised_quality_name = prototypes.quality[entry.quality_name].localised_name
    return { iname = localised_name, qname = localised_quality_name }
  end
  return { iname = entry.item_name, qname = entry.quality_name }
end

return utils