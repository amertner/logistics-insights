-- A simple tick counter object that can be used to keep track of ticks in a game.
-- It can be paused and resumed, and returns the total time it was running

---@class TickCounter
---@field _start_tick number -- The tick when the counter was started (PRIVATE)
---@field _paused boolean -- Whether the counter is currently paused (PRIVATE)
---@field _pause_tick number|nil -- The tick when the counter was paused (PRIVATE)
---@field _accumulated_time number -- The total time accumulated while the counter was running (PRIVATE)
local TickCounter = {}
TickCounter.__index = TickCounter
script.register_metatable("logistics-insights-TickCounter", TickCounter)

-- Create a new tick counter
---@param initial_tick? number Optional initial tick value, otherwise it's the current tick
---@return TickCounter
function TickCounter.new(initial_tick)
  local self = setmetatable({}, TickCounter)
  self._start_tick = initial_tick or game.tick
  self._paused = false
  self._pause_tick = nil
  self._accumulated_time = 0
  return self
end

-- Pause the counter
---@return boolean true if paused, false if already paused
function TickCounter:pause()
  if not self._paused then
    self._pause_tick = game.tick
    self._accumulated_time = self._accumulated_time + (self._pause_tick - self._start_tick)
    self._paused = true
    return true
  end
  return false -- Already paused
end

-- Resume the counter
---@return boolean true if resumed, false if already running
function TickCounter:resume()
  if self._paused then
    self._start_tick = game.tick
    self._paused = false
    return true
  end
  return false -- Already running
end

-- Reset the counter
function TickCounter:reset()
  self._start_tick = game.tick
  self._paused = false
  self._pause_tick = nil
  self._accumulated_time = 0
end

-- Reset the counter, but keep the pause state and time
function TickCounter:reset_keep_pause()
  self._start_tick = game.tick
  self._accumulated_time = 0
end

-- Get current elapsed time (including accumulated time from previous runs)
---@return number Total elapsed ticks
function TickCounter:elapsed()
  if self._paused then
    return self._accumulated_time
  else
    return self._accumulated_time + (game.tick - self._start_tick)
  end
end

-- Get total unpaused time
---@return number Total ticks the counter was running
function TickCounter:total_unpaused()
  return self:elapsed()
end

-- Check if counter is currently paused
---@return boolean true if paused, false if running
function TickCounter:is_paused()
  return self._paused
end

return TickCounter