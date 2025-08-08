--- Manage pausing and dependencies between things that might be paused
local pause_manager = {}
local mini_button = require("scripts.mainwin.mini_button")

--- Array of paused item names
---@alias PausedItems string[]

pause_manager.names = {
  window = "window", -- For pausing everything when the window is minimised
  delivery = "delivery",
  history = "history",
  activity = "activity",
  suggestions = "suggestions",
  undersupply = "undersupply"
}

-- How different pause states depend. Don't make circular dependencies!
pause_manager.dependencies = {
  -- History depends on Delivery being enabled
  history = { "window", "delivery" },
  -- Suggestions depends on Activity, i.e. Cell scanning
  suggestions = { "window", "activity" },
  -- Undersupply depends on Delivery being enabled
  undersupply = { "window", "delivery" },
  -- Delivery and Activity are always active, except perhaps when the window is minimised
  delivery = { "window" },
  activity = { "window" },
}

--- Enable all pause items, i.e. set them to running state (on window create/recreate)
function pause_manager.enable_all()
  -- Update all mini buttons to reflect the new state
  for name in pairs(pause_manager.names) do
    mini_button.update_paused_state(name, true)
  end
end

local function enable_dependent_buttons(name, enabled)
  for dep_name, deps in pairs(pause_manager.dependencies) do
    if deps and #deps > 0 then
      for _, dep in ipairs(deps) do
        if dep == name then
          mini_button.set_enabled(dep_name, enabled)
        end
      end
    end
  end
end

--- Set the pause state for a specific item
---@param paused_items PausedItems The array of paused item names
---@param name string The name of the item to pause/unpause
---@param is_paused boolean Whether the item should be paused
function pause_manager.set_paused(paused_items, name, is_paused)
  if not pause_manager.names[name] then
    return
  end

  -- Find if item is already in the paused array
  local index = nil
  for i, paused_name in ipairs(paused_items) do
    if paused_name == name then
      index = i
      break
    end
  end

  if is_paused then
    -- Add to array if not already there
    if not index then
      table.insert(paused_items, name)
      -- Reflect the new pause button state
      mini_button.update_paused_state(name, true)
      -- Disable pause buttons that depend on this item
      enable_dependent_buttons(name, false)
    end
  else
    -- Remove from array if present
    if index then
      table.remove(paused_items, index)
      -- Also reflect the pause button state
      mini_button.update_paused_state(name, false)
      -- Enable pause buttons that depend on this item
      enable_dependent_buttons(name, true)
    end
  end
end

--- Check if an item is paused, considering dependencies
---@param paused_items PausedItems The array of paused item names
---@param name string The name of the item to check
---@return boolean Whether the item is effectively paused
function pause_manager.is_paused(paused_items, name)
  -- Check if this item is explicitly paused
  for _, paused_name in ipairs(paused_items) do
    if paused_name == name then
      return true
    end
  end

  -- Check if any of its dependencies are paused
  local deps = pause_manager.dependencies[name]
  if deps then
    for _, dependency in ipairs(deps) do
      if pause_manager.is_paused(paused_items, dependency) then
        return true -- If any dependency is paused, this item is paused
      end
    end
  end

  return false
end

--- Check if an item is running (i.e. not paused)
---@param paused_items PausedItems The array of paused item names
---@param name string The name of the item to check
---@return boolean Whether the item is effectively paused
function pause_manager.is_running(paused_items, name)
  return not pause_manager.is_paused(paused_items, name)
end

--- Toggle the pause state for a specific item
---@param paused_items PausedItems The array of paused item names
---@param name string The name of the item to toggle
---@return boolean The new pause state
function pause_manager.toggle_paused(paused_items, name)
  local current_state = pause_manager.is_explicitly_paused(paused_items, name)
  local new_state = not current_state
  pause_manager.set_paused(paused_items, name, new_state)
  return new_state
end

--- Get all currently paused items (explicitly paused only)
---@param paused_items PausedItems The array of paused item names
---@return PausedItems Array of explicitly paused item names
function pause_manager.get_paused_items(paused_items)
  return paused_items
end

--- Check if an item is explicitly paused (not considering dependencies)
---@param paused_items PausedItems The array of paused item names
---@param name string The name of the item to check
---@return boolean Whether the item is explicitly paused
function pause_manager.is_explicitly_paused(paused_items, name)
  for _, paused_name in ipairs(paused_items) do
    if paused_name == name then
      return true
    end
  end
  return false
end

return pause_manager