local mock = require("tests.mocks.factorio")

-- Which network gets analysed next, and how often. Analysis is the expensive part, a pass over
-- every storage and requester, so a network only earns the two-second foreground cadence while a
-- player has the main window open on it. A player merely standing in a network with the window
-- closed used to get that cadence too, keeping analysis running continuously with nothing shown.
describe("analysis_coordinator.find_network_to_analyse", function()
  local analysis_coordinator, network_data

  before_each(function()
    mock.fresh()
    storage.global = { background_refresh_interval_ticks = 600, background_refresh_interval_secs = 10,
      calculate_undersupply = true }
    storage.players = {}
    storage.networks = {}
    storage.analysing_networkdata = nil
    network_data = require("scripts.network-data")
    analysis_coordinator = require("scripts.analysis-coordinator")
    game.tick = 10000
  end)

  local function a_network(id, players, analysed_ago)
    local lua_network = { valid = true, network_id = id }
    local nwd = { id = id, players_set = {}, last_analysed_tick = game.tick - analysed_ago,
      _lua_network = lua_network }
    for _, idx in ipairs(players) do nwd.players_set[idx] = true end
    storage.networks[id] = nwd
    return nwd
  end

  local function a_player(index, window_open)
    storage.players[index] = { player_index = index, settings = {}, bots_window_visible = window_open }
  end

  it("analyses a watched network after two seconds", function()
    a_player(1, true)
    local nwd = a_network(1, {1}, 3 * 60)
    assert.are.equal(nwd, analysis_coordinator.find_network_to_analyse())
  end)

  it("does not give a network the foreground cadence just because a player is standing in it", function()
    a_player(1, false)
    a_network(1, {1}, 3 * 60)
    assert.is_nil(analysis_coordinator.find_network_to_analyse())
  end)

  it("still analyses that network at the background cadence", function()
    a_player(1, false)
    local nwd = a_network(1, {1}, 601)
    assert.are.equal(nwd, analysis_coordinator.find_network_to_analyse())
  end)

  it("prefers the watched network over an older unwatched one", function()
    a_player(1, true)
    local watched = a_network(1, {1}, 3 * 60)
    a_network(2, {}, 5000)
    assert.are.equal(watched, analysis_coordinator.find_network_to_analyse())
  end)

  it("leaves unwatched networks alone when background refresh is off", function()
    storage.global.background_refresh_interval_ticks = 0
    a_player(1, false)
    a_network(1, {1}, 5000)
    a_network(2, {}, 5000)
    assert.is_nil(analysis_coordinator.find_network_to_analyse())
  end)
end)
