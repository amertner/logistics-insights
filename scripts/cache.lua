-- cache.lua - Generic caching system for frequently accessed data
local cache = {}

-- Use Factorio's table_size if available, or define our own
local table_size = _ENV.table_size or function(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

-- Create a new cache
---@param generator function A function that generates a value for a key when it doesn't exist in the cache
function cache.new(generator)
  local new_cache = {
    -- Internal storage for cached values
    _storage = {},
    
    -- Generator function for creating new entries
    _generator = generator or function(key) return key end,
    
    -- Get a value from the cache, generating it if it doesn't exist
    -- @param key The cache key
    -- @param ... Additional parameters to pass to the generator function
    -- @return The cached or newly generated value
    get = function(self, key, ...)
      if key == nil then
        return nil
      end
      
      if self._storage[key] == nil then
        self._storage[key] = self._generator(key, ...)
      end
      
      return self._storage[key]
    end,
    
    -- Set a value in the cache directly
    -- @param key The cache key
    -- @param value The value to store
    set = function(self, key, value)
      if key ~= nil then
        self._storage[key] = value
      end
    end,
    
    -- Check if a key exists in the cache
    -- @param key The cache key
    -- @return Boolean indicating whether the key exists
    has = function(self, key)
      return self._storage[key] ~= nil
    end,
    
    -- Remove a specific entry from the cache
    -- @param key The cache key to remove
    remove = function(self, key)
      self._storage[key] = nil
    end,
    
    -- Clear all entries from the cache
    clear = function(self)
      self._storage = {}
    end,
    
    -- Get the number of entries in the cache
    -- @return Number of entries
    size = function(self)
      return table_size(self._storage)
    end,
    
    -- Get all keys in the cache
    -- @return Array of keys
    keys = function(self)
      local keys_array = {}
      for k, _ in pairs(self._storage) do
        table.insert(keys_array, k)
      end
      return keys_array
    end
  }
  
  return new_cache
end

-- Return the module
return cache
