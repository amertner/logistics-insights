-- A simple tick counter object that can be used to keep track of ticks in a game.
-- The tick counter can be paused and resumed.
-- The tick counter can return the elapsed time since it was started or since it was last paused
-- The tick counter can return the total amount of time it was unpaused

local TickCounter = {}
TickCounter.__index = TickCounter

---@class TickCounter

-- Create a new tick counter
function TickCounter.new(initial_tick)
  local self = setmetatable({}, TickCounter)
  self.start_tick = initial_tick or game.tick
  self.paused = false
  self.pause_tick = nil
  self.accumulated_time = 0
  return self
end

-- Pause the counter
function TickCounter:pause()
  if not self.paused then
    self.pause_tick = game.tick
    self.accumulated_time = self.accumulated_time + (self.pause_tick - self.start_tick)
    self.paused = true
    return true
  end
  return false -- Already paused
end

-- Resume the counter
function TickCounter:resume()
  if self.paused then
    self.start_tick = game.tick
    self.paused = false
    return true
  end
  return false -- Already running
end

-- Toggle pause state
function TickCounter:toggle()
  if self.paused then
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
  self.start_tick = game.tick
  self.paused = false
  self.pause_tick = nil
  self.accumulated_time = 0
end

-- Get current elapsed time (including accumulated time from previous runs)
function TickCounter:elapsed()
  if self.paused then
    return self.accumulated_time
  else
    return self.accumulated_time + (game.tick - self.start_tick)
  end
end

-- Get time elapsed since the counter was started or last resumed
function TickCounter:current_elapsed()
  if self.paused then
    return 0
  else
    return game.tick - self.start_tick
  end
end

-- Get time elapsed since the counter was paused
function TickCounter:time_since_paused()
  if self.paused then
    return game.tick - self.pause_tick
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
  return self.paused
end

-- Convert to a descriptive string
function TickCounter:to_string()
  local status = self.paused and "paused" or "running"
  return string.format("TickCounter: %s, elapsed: %d ticks", status, self:elapsed())
end

return TickCounter