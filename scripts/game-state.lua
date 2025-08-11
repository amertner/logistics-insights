-- Manage freezing, unfreezing and single-stepping the game
local game_state = {}

local player_data = require("scripts.player-data")

--- Initialize the game state with UI button references
---@param player_table PlayerData The player's data table
---@param ui_unfreeze LuaGuiElement|nil The unfreeze button element
---@param ui_freeze LuaGuiElement|nil The freeze button element
function game_state.init(player_table, ui_unfreeze, ui_freeze)
  game.tick_paused = false
  game.ticks_to_run = 0
  player_table.ui["freeze_button"] = ui_freeze
  player_table.ui["unfreeze_button"] = ui_unfreeze
end

--- Freeze the game by pausing ticks
function game_state.freeze_game(player_table)
  game.tick_paused = true
  game_state.force_update_ui(player_table, false, true)
end

--- Unfreeze the game by resuming ticks
---@param player_table any Unused parameter for compatibility
function game_state.unfreeze_game(player_table)
  game.tick_paused = false
  game_state.force_update_ui(player_table, false, true)
end

--- Step the game by one tick
function game_state.step_game(player_table)
  game.tick_paused = true
  game.ticks_to_run = 1
  game_state.force_update_ui(player_table, true, true)
end

--- Update the UI button states to reflect current game state
--- Unusually, need to do this for ALL connected players
---@param player_table PlayerData The player's data table
---@param stepping boolean Whether the game is being stepped
---@param message boolean|nil Whether to send a message to players
function game_state.force_update_ui(player_table, stepping, message)
  local is_paused = game_state.is_frozen()

  -- Iterate all connected players; update their button states if present
  for _, player in pairs(game.connected_players) do
    if player and player.valid then
      local pt = player_data.get_player_table(player.index)
      if pt and pt.ui then
        local freeze_button = pt.ui["freeze_button"]
        local unfreeze_button = pt.ui["unfreeze_button"]
        if freeze_button and unfreeze_button then
          unfreeze_button.enabled = is_paused
          freeze_button.enabled = not is_paused
        end
      end
    end
  end

  -- Send one announcement using the first triggering player's name/color if available
  if message and player_table then
    local player = game.players[player_table.player_index]
    if player and player.valid then
      local alertstr
      if is_paused then
        if stepping then
          alertstr = "game-state.game-stepped-1li-2player_3color"
        else
          alertstr = "game-state.game-frozen-1li-2player_3color"
        end
      else
        alertstr = "game-state.game-unfrozen-1li-2player_3color"
      end
      game.print({"", {alertstr, {"mod-name.logistics-insights"}, player.name,
        {"game-state.rgb", player.color.r, player.color.g, player.color.b}}})
    end
  end
end

--- Check if the game is currently paused
---@return boolean True if the game is paused, false otherwise
function game_state.is_frozen()
  return game.tick_paused
end

--- Check if the UI buttons need to be initialized
---@return boolean True if buttons need initialization, false otherwise
function game_state.needs_buttons(player_table)
  local freeze_button = player_table.ui["freeze_button"]
  local unfreeze_button = player_table.ui["unfreeze_button"]
  return unfreeze_button == nil or freeze_button == nil
end

return game_state