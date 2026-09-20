local mock = require("tests.mocks.factorio")

-- Freezing is game-wide: one player freezes to look at bots, and every player's window shows it.
-- Registering a window's buttons must not touch that state, or any window rebuild (a setting
-- change, a player joining) resumes the game under the player who froze it.
describe("game_state", function()
  local game_state

  before_each(function()
    mock.fresh()
    storage.players = {}
    game_state = require("scripts.game-state")
  end)

  it("registering a window's buttons leaves a frozen game frozen", function()
    game.tick_paused = true
    game.ticks_to_run = 0
    local player_table = { player_index = 1, ui = {} }
    local freeze, unfreeze = { name = "freeze" }, { name = "unfreeze" }

    game_state.init(player_table, unfreeze, freeze)

    assert.is_true(game.tick_paused)
    assert.are.equal(freeze, player_table.ui.freeze_button)
    assert.are.equal(unfreeze, player_table.ui.unfreeze_button)
    assert.is_false(game_state.needs_buttons(player_table))
  end)

  it("freeze and unfreeze change the shared state", function()
    game.tick_paused = false
    game.connected_players = {}
    game.players = {}
    game_state.freeze_game({ player_index = 1 })
    assert.is_true(game_state.is_frozen())
    game_state.unfreeze_game({ player_index = 1 })
    assert.is_false(game_state.is_frozen())
  end)
end)
