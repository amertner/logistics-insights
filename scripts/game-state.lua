-- Manage freezing, unfreezing and single-stepping the game
local game_state = {}

function game_state.init(ui_unfreeze, ui_freeze)
  game.tick_paused = false
  game.ticks_to_run = 0
  game_state.unfreeze_button = ui_unfreeze or nil
  game_state.freeze_button = ui_freeze or nil
end

function game_state.freeze_game()
  game.tick_paused = true
  game_state.force_update_ui()
end

function game_state.unfreeze_game(p)
  game.tick_paused = false
  game_state.force_update_ui()
end

function game_state.step_game()
  game.tick_paused = true
  game.ticks_to_run = 1
  game_state.force_update_ui()
end

function game_state.force_update_ui()
  if game_state.unfreeze_button and game_state.freeze_button then
    game_state.unfreeze_button.enabled = game_state.is_paused()
    game_state.freeze_button.enabled = not game_state.is_paused()
  end
end

function game_state.is_paused()
  return game.tick_paused
end

function game_state.needs_buttons()
  return game_state.unfreeze_button == nil or game_state.freeze_button == nil
end

return game_state