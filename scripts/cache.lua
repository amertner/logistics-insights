-- A memo table: a value is generated the first time its key is asked for, and kept until cleared
local cache = {}

--- Create a new cache
---@param generator fun(key: any, ...): any Makes the value for a key; extra get() arguments are passed on
function cache.new(generator)
  return {
    _storage = {},
    _generator = generator or function(key) return key end,

    --- The value for a key, generated on first use
    get = function(self, key, ...)
      if key == nil then
        return nil
      end
      local value = self._storage[key]
      if value == nil then
        value = self._generator(key, ...)
        self._storage[key] = value
      end
      return value
    end,

    --- Forget every value
    clear = function(self)
      self._storage = {}
    end,
  }
end

return cache
