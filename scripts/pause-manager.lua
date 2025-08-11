--- Manage pausing and dependencies between things that might be paused
local pause_manager = {}
--local player_data = require("scripts.player-data")
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
--- @param player_table PlayerData The player's data table
function pause_manager.enable_all(player_table)
  -- Update all mini buttons to reflect the new state
  for name in pairs(pause_manager.names) do
    mini_button.update_paused_state(player_table, name, true)
  end
end

--- @param player_table PlayerData The player's data table
--- @param name string The name of the button whose dependencies we want to enable/disable
--- @param enabled boolean Whether to enable or disable the dependent buttons
local function enable_dependent_buttons(player_table, name, enabled)
  for dep_name, deps in pairs(pause_manager.dependencies) do
    if deps and #deps > 0 then
      for _, dep in ipairs(deps) do
        if dep == name then
          mini_button.set_enabled(player_table, dep_name, enabled)
        end
      end
    end
  end
end

--- Set the pause state for a specific item
--- @param player_table PlayerData The player's data table
---@param name string The name of the item to pause/unpause
---@param is_paused boolean Whether the item should be paused
function pause_manager.set_paused(player_table, name, is_paused)
  if not pause_manager.names[name] then
    return
  end

  -- Find if item is already in the paused array
  local index = nil
  for i, paused_name in ipairs(player_table.paused_items) do
    if paused_name == name then
      index = i
      break
    end
  end

  if is_paused then
    -- Add to array if not already there
    if not index then
      table.insert(player_table.paused_items, name)
      -- Reflect the new pause button state
      mini_button.update_paused_state(player_table, name, true)
      -- Disable pause buttons that depend on this item
      enable_dependent_buttons(player_table, name, false)
    end
  else
    -- Remove from array if present
    if index then
      table.remove(player_table.paused_items, index)
      -- Also reflect the pause button state
      mini_button.update_paused_state(player_table, name, false)
      -- Enable pause buttons that depend on this item
      enable_dependent_buttons(player_table, name, true)
    end
  end
end

--- Check if an item is paused, considering dependencies
---@param player_table PlayerData The player's data table
---@param name string The name of the item to check
---@return boolean Whether the item is effectively paused
function pause_manager.is_paused(player_table, name)
  -- Check if this item is explicitly paused
  for _, paused_name in ipairs(player_table.paused_items) do
    if paused_name == name then
      return true
    end
  end

  -- Check if any of its dependencies are paused
  local deps = pause_manager.dependencies[name]
  if deps then
    for _, dependency in ipairs(deps) do
      if pause_manager.is_paused(player_table, dependency) then
        return true -- If any dependency is paused, this item is paused
      end
    end
  end

  return false
end

--- Check if an item is running (i.e. not paused)
---@param player_table PlayerData The player's data table
---@param name string The name of the item to check
---@return boolean Whether the item is effectively paused
function pause_manager.is_running(player_table, name)
  return not pause_manager.is_paused(player_table, name)
end

--- Toggle the pause state for a specific item
---@param player_table PlayerData The player's data table
---@param name string The name of the item to toggle
---@return boolean The new pause state
function pause_manager.toggle_paused(player_table, name)
  local current_state = pause_manager.is_explicitly_paused(player_table, name)
  local new_state = not current_state
  pause_manager.set_paused(player_table, name, new_state)
  return new_state
end

--- Get all currently paused items (explicitly paused only)
---@param player_table PlayerData The player's data table
---@return PausedItems Array of explicitly paused item names
function pause_manager.get_paused_items(player_table)
  return player_table.paused_items
end

--- Check if an item is explicitly paused (not considering dependencies)
---@param player_table PlayerData The player's data table
---@param name string The name of the item to check
---@return boolean Whether the item is explicitly paused
function pause_manager.is_explicitly_paused(player_table, name)
  for _, paused_name in ipairs(player_table.paused_items) do
    if paused_name == name then
      return true
    end
  end
  return false
end

return pause_manager