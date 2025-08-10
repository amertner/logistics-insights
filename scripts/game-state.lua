-- Manage freezing, unfreezing and single-stepping the game
local game_state = {}

local player_data = require("scripts.player-data")

--- Initialize the game state with UI button references
---@param ui_unfreeze LuaGuiElement|nil The unfreeze button element
---@param ui_freeze LuaGuiElement|nil The freeze button element
function game_state.init(ui_unfreeze, ui_freeze)
  game.tick_paused = false
  game.ticks_to_run = 0
  game_state.unfreeze_button = ui_unfreeze or nil
  game_state.freeze_button = ui_freeze or nil
end

--- Freeze the game by pausing ticks
function game_state.freeze_game(player_table)
  game.tick_paused = true
  game_state.force_update_ui(player_table)
end

--- Unfreeze the game by resuming ticks
---@param p any Unused parameter for compatibility
function game_state.unfreeze_game(player_table)
  game.tick_paused = false
  game_state.force_update_ui(player_table)
end

--- Step the game by one tick
function game_state.step_game(player_table)
  game.tick_paused = true
  game.ticks_to_run = 1
  game_state.force_update_ui(player_table)
end

--- Update the UI button states to reflect current game state
---@param player_table PlayerData|nil The player's data table
function game_state.force_update_ui(player_table)
  if game_state.unfreeze_button and game_state.freeze_button then
    local is_paused = game_state.is_paused()
    if player_table then
      local player = game.get_player(player_table.player_index)
      if player and player.valid then
        local alertstr
        if is_paused then
          alertstr = "game-state.game-frozen-1li-2player_3color"
        else
          alertstr = "game-state.game-unfrozen-1li-2player_3color"
        end
        game.print({"", {alertstr, {"mod-name.logistics-insights"}, player.name, {"game-state.rgb", player.color.r, player.color.g, player.color.b}}})
      end
    end
    game_state.unfreeze_button.enabled = is_paused
    game_state.freeze_button.enabled = not is_paused
  end
end

--- Check if the game is currently paused
---@return boolean True if the game is paused, false otherwise
function game_state.is_paused()
  return game.tick_paused
end

--- Check if the UI buttons need to be initialized
---@return boolean True if buttons need initialization, false otherwise
function game_state.needs_buttons()
  return game_state.unfreeze_button == nil or game_state.freeze_button == nil
end

return game_state