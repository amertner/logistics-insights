-- A simple tick counter object that can be used to keep track of ticks in a game.
-- The tick counter can be paused and resumed.
-- The tick counter can return the elapsed time since it was started or since it was last paused
-- The tick counter can return the total amount of time it was unpaused

local TickCounter = {}

--- A simple tick counter object that can be used to keep track of ticks in a game.
--- 
--- IMPORTANT: All fields with underscore prefix are considered PRIVATE 
--- and should not be accessed directly. Use the provided methods instead.
---@class TickCounter
---@field reset fun(self: TickCounter) -- Resets the counter to the current tick
---@field pause fun(self: TickCounter) -- Pauses the counter
---@field resume fun(self: TickCounter) -- Resumes the counter
---@field toggle fun(self: TickCounter) -- Toggles the pause state of the counter
---@field is_paused fun(self: TickCounter) -- Returns whether the counter is currently paused
---@field _start_tick number -- The tick when the counter was started (PRIVATE)
---@field _paused boolean -- Whether the counter is currently paused (PRIVATE)
---@field _pause_tick number -- The tick when the counter was paused (PRIVATE)
---@field _accumulated_time number -- The total time accumulated while the counter was running (PRIVATE)
TickCounter.__index = TickCounter
script.register_metatable("logistics-insights-TickCounter", TickCounter)

-- Create a new tick counter
function TickCounter.new(initial_tick)
  local self = setmetatable({}, TickCounter)
  self._start_tick = initial_tick or game.tick
  self._paused = false
  self._pause_tick = nil
  self._accumulated_time = 0
  return self
end

-- Pause the counter
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
function TickCounter:resume()
  if self._paused then
    self._start_tick = game.tick
    self._paused = false
    return true
  end
  return false -- Already running
end

-- Toggle pause state
function TickCounter:toggle()
  if self._paused then
    return self:resume()
  else
    return self:pause()
  end
end

-- Set pause state directly
function TickCounter:set_paused(paused)
  if paused then
    return self:pause()
  else
    return self:resume()
  end
end

-- Reset the counter
function TickCounter:reset()
  self._start_tick = game.tick
  self._paused = false
  self._pause_tick = nil
  self._accumulated_time = 0
end

-- Get current elapsed time (including accumulated time from previous runs)
function TickCounter:elapsed()
  if self._paused then
    return self._accumulated_time
  else
    return self._accumulated_time + (game.tick - self._start_tick)
  end
end

-- Get time elapsed since the counter was started or last resumed
function TickCounter:current_elapsed()
  if self._paused then
    return 0
  else
    return game.tick - self._start_tick
  end
end

-- Get time elapsed since the counter was paused
function TickCounter:time_since_paused()
  if self._paused then
    return game.tick - self._pause_tick
  else
    return 0
  end
end

-- Get total unpaused time
function TickCounter:total_unpaused()
  return self:elapsed()
end

-- Check if counter is currently paused
function TickCounter:is_paused()
  return self._paused
end

-- Convert to a descriptive string
function TickCounter:to_string()
  local status = self._paused and "paused" or "running"
  return string.format("TickCounter: %s, elapsed: %d ticks", status, self:elapsed())
end

return TickCounter