--- Miscellaneous utility functions for the Logistics Insights mod
local utils = {}

---@alias QualityTable table<string, number> -- Quality name to count mapping

--- Check if a string starts with a given prefix
--- @param str string The string to check
--- @param prefix string The prefix to look for
--- @return boolean True if the string starts with the prefix
function utils.starts_with(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

--- Get a random element from a list
--- @param list table|nil The list to select from (must be array-like with numeric indices)
--- @return any|nil The randomly selected element, or nil if list is empty or nil
function utils.get_random(list)
  if list and #list ~= table_size(list) then
    assert(false, "Need to use table_size!")
  end
  if not list or #list == 0 then
    return nil
  end
  local index = math.random(1, #list)
  return list[index]
end

--- Accumulate quality counts in a quality table
--- @param quality_table QualityTable The table to accumulate quality counts in
--- @param quality string The quality name to increment
--- @param count number The count to add for this quality
function utils.accumulate_quality(quality_table, quality, count)
  if not quality_table[quality] then
    quality_table[quality] = 0
  end
  quality_table[quality] = quality_table[quality] + count
end

-- Create a table to store combined (name/quality) keys for reduced memory fragmentation
local item_quality_keys = {}

--- Get a cached delivery key for item name and quality combination
--- @param item_name string The name of the item
--- @param quality string The quality name (e.g., "normal", "uncommon", etc.)
--- @return string The cached delivery key
function utils.get_item_quality_key(item_name, quality)
  local cache_key = item_name .. ":" .. quality
  local key = item_quality_keys[cache_key]
  if not key then
    key = cache_key
    item_quality_keys[cache_key] = key
  end
  return key
end

return utils