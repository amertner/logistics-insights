local mock = require("tests.mocks.factorio")

-- Leaving a network used to destroy its delivery history outright. Remote view moves the player's
-- position, so clicking a long trip to see it on the map counted as leaving, and threw away the
-- very history the trip came from. Leaving now only freezes the history; it is dropped once the
-- network has gone unwatched for UNOBSERVED_HISTORY_GRACE_TICKS.
describe("network observation", function()
  local network_data, GRACE

  before_each(function()
    mock.fresh()
    storage.global = { show_all_networks = true }
    storage.players = {}
    storage.networks = {}
    network_data = require("scripts.network-data")
    GRACE = network_data.UNOBSERVED_HISTORY_GRACE_TICKS
  end)

  -- ─── Helpers ──────────────────────────────────────────────────────

  --- A player table with just enough on it for the network code
  local function a_player(index)
    local player_table = { player_index = index, network = nil, settings = {} }
    storage.players[index] = player_table
    return player_table
  end

  --- A mock LuaLogisticNetwork that create_networkdata will accept
  local function a_network(id)
    return {
      valid = true,
      network_id = id,
      force = { name = "player" },
      cells = { { owner = { valid = true, surface = { name = "nauvis" } } } },
    }
  end

  local function arrive(player_table, network)
    local old_id = player_table.network and player_table.network.network_id or nil
    network_data.player_changed_networks(player_table, old_id, network)
    -- Pretend the network still exists, so expiry doesn't remove it as gone
    local nwd = storage.networks[network.network_id]
    nwd._lua_network = network
    return nwd
  end

  local function leave(player_table)
    network_data.player_changed_networks(player_table, player_table.network.network_id, nil)
  end

  local function with_history(nwd)
    nwd.delivery_history["iron-plate:normal"] = { item_name = "iron-plate", count = 10, deliveries = 2 }
    return nwd
  end

  local function advance(ticks)
    game.tick = game.tick + ticks
  end

  -- ─── What is listed ───────────────────────────────────────────────

  describe("is_listed", function()
    it("lists every network while Show all networks is on", function()
      local p = a_player(1)
      local nwd = arrive(p, a_network(1))
      leave(p)
      assert.is_true(network_data.is_listed(nwd))
      assert.are.equal(1, network_data.listed_network_count())
    end)

    it("lists only watched networks when it is off, though the unwatched one is kept for its history", function()
      storage.global.show_all_networks = false
      local p1, p2 = a_player(1), a_player(2)
      local left = arrive(p1, a_network(1))
      local watched = arrive(p2, a_network(2))
      leave(p1)
      assert.is_not_nil(storage.networks[1]) -- Kept, inside the grace period
      assert.is_false(network_data.is_listed(left))
      assert.is_true(network_data.is_listed(watched))
      assert.are.equal(1, network_data.listed_network_count())
    end)

    it("leaves an unlisted network's suggestions out of the totals", function()
      storage.global.show_all_networks = false
      local p = a_player(1)
      local nwd = arrive(p, a_network(1))
      nwd.suggestions:create_or_age_suggestion("x", 1, "entity/roboport", "low", false, "")
      assert.are.equal(1, network_data.get_total_suggestions_and_undersupply().suggestions)
      leave(p)
      assert.are.equal(0, network_data.get_total_suggestions_and_undersupply().suggestions)
    end)
  end)

  -- ─── Background scan selection ────────────────────────────────────

  describe("get_next_background_network", function()
    before_each(function()
      storage.global.background_refresh_interval_ticks = 600
      game.tick = 10000
    end)

    it("skips the network being foreground scanned, however old its last scan", function()
      local p = a_player(1)
      local watched = arrive(p, a_network(1))
      watched.last_scanned_tick = 0 -- Oldest of all
      local other = arrive(a_player(2), a_network(2))
      other.last_scanned_tick = 5000
      storage.fg_refreshing_network_id = 1

      assert.are.equal(other, network_data.get_next_background_network())

      storage.fg_refreshing_network_id = nil
      assert.are.equal(watched, network_data.get_next_background_network())
    end)

    it("returns nothing when the only eligible network is the foreground one", function()
      local nwd = arrive(a_player(1), a_network(1))
      nwd.last_scanned_tick = 0
      storage.fg_refreshing_network_id = 1
      assert.is_nil(network_data.get_next_background_network())
    end)
  end)

  -- ─── Leaving freezes, rather than destroys ────────────────────────

  it("keeps the history when the last player leaves", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))

    advance(600)
    leave(player_table)

    assert.is_not_nil(storage.networks[1])
    assert.are.equal(10, nwd.delivery_history["iron-plate:normal"].count)
    assert.are.equal(game.tick, nwd.unobserved_since)
    assert.is_true(nwd.history_timer:is_paused())
  end)

  it("still has the history when the player comes straight back", function()
    local player_table = a_player(1)
    local network = a_network(1)
    local nwd = with_history(arrive(player_table, network))

    leave(player_table)
    advance(GRACE / 2)
    arrive(player_table, network)

    assert.are.equal(10, nwd.delivery_history["iron-plate:normal"].count)
    assert.is_nil(nwd.unobserved_since)
    assert.is_false(nwd.history_timer:is_paused())
  end)

  it("counts only the time the network was actually watched", function()
    local player_table = a_player(1)
    local network = a_network(1)
    local nwd = arrive(player_table, network)

    advance(600)
    leave(player_table)
    advance(GRACE / 2) -- Not watched, so this must not be counted
    arrive(player_table, network)
    advance(300)

    assert.are.equal(900, nwd.history_timer:total_unpaused())
  end)

  it("forgets the bots a background scan saw when the player returns", function()
    local player_table = a_player(1)
    local network = a_network(1)
    local nwd = arrive(player_table, network)

    leave(player_table)
    nwd.last_pass_bots_seen = { [7] = 1 } -- A background pass kept looking
    arrive(player_table, network)

    assert.are.equal(0, table_size(nwd.last_pass_bots_seen))
  end)

  it("forgets where bots were picking up when the player returns", function()
    local player_table = a_player(1)
    local network = a_network(1)
    local nwd = arrive(player_table, network)
    nwd.bot_pickup_positions = { [7] = { x = 0, y = 0, item_name = "iron-plate", seen = game.tick } }

    leave(player_table)
    advance(GRACE / 2) -- Only a bot pass prunes pickups, and none need have run while away
    arrive(player_table, network)

    -- Kept, it would be matched to whatever bot 7 carries next and recorded as a measured start
    assert.are.equal(0, table_size(nwd.bot_pickup_positions))
  end)

  -- ─── Expiry ───────────────────────────────────────────────────────

  it("drops the history once the grace period has passed", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))
    local gen = nwd.delivery_history_gen

    leave(player_table)
    advance(GRACE + 1)
    network_data.expire_unobserved_history()

    assert.is_not_nil(storage.networks[1]) -- Kept, because show_all_networks is true
    assert.are.equal(0, table_size(nwd.delivery_history))
    assert.is_true(nwd.delivery_history_gen > gen) -- So the row is redrawn
    assert.is_true(nwd.history_timer:is_paused())
    assert.are.equal(0, nwd.history_timer:total_unpaused())
    assert.is_nil(nwd.unobserved_since) -- Expired once is enough
  end)

  it("leaves a network alone while it is still inside the grace period", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))

    leave(player_table)
    local stamped_at = nwd.unobserved_since
    advance(GRACE - 1)
    network_data.expire_unobserved_history()

    assert.are.equal(10, nwd.delivery_history["iron-plate:normal"].count)
    assert.are.equal(stamped_at, nwd.unobserved_since)
  end)

  it("starts a fresh history and a fresh clock when an expired network is revisited", function()
    local player_table = a_player(1)
    local network = a_network(1)
    local nwd = with_history(arrive(player_table, network))

    leave(player_table)
    advance(GRACE + 1)
    network_data.expire_unobserved_history()
    advance(600)
    arrive(player_table, network)
    advance(120)

    assert.is_false(nwd.history_timer:is_paused())
    assert.are.equal(120, nwd.history_timer:total_unpaused())
    assert.is_nil(nwd.unobserved_since)
  end)

  it("removes the network outright when unobserved networks are not kept", function()
    storage.global.show_all_networks = false
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))
    local cleaned = false
    nwd.bot_chunker.cleanup = function() cleaned = true end

    leave(player_table)
    advance(GRACE + 1)
    network_data.expire_unobserved_history()

    assert.is_nil(storage.networks[1])
    assert.is_true(cleaned) -- Went through remove_network, so the fetcher references were released
  end)

  it("clears a stale stamp if somebody is watching the network again", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))
    nwd.unobserved_since = game.tick -- Stamped, but the player never actually left

    advance(GRACE + 1)
    network_data.expire_unobserved_history()

    assert.is_not_nil(storage.networks[1])
    assert.are.equal(10, nwd.delivery_history["iron-plate:normal"].count)
    assert.is_nil(nwd.unobserved_since)
  end)

  -- ─── Several players ──────────────────────────────────────────────

  it("starts the clock only when the last player leaves", function()
    local first, second = a_player(1), a_player(2)
    local network = a_network(1)
    local nwd = arrive(first, network)
    arrive(second, network)

    leave(first)
    assert.is_nil(nwd.unobserved_since)
    assert.is_false(nwd.history_timer:is_paused())

    leave(second)
    assert.is_not_nil(nwd.unobserved_since)
    assert.is_true(nwd.history_timer:is_paused())
  end)

  it("does not reset the clock of a player already watching the network", function()
    local first, second = a_player(1), a_player(2)
    local network = a_network(1)
    local nwd = arrive(first, network)

    advance(600)
    arrive(second, network)

    assert.are.equal(600, nwd.history_timer:total_unpaused())
  end)

  -- ─── Logging out takes the same path as walking out ───────────────

  it("keeps the history when the last player logs out", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))

    network_data.remove_player_index(1) -- on_player_left_game

    assert.are.equal(10, nwd.delivery_history["iron-plate:normal"].count)
    assert.is_not_nil(nwd.unobserved_since)
    assert.is_true(nwd.history_timer:is_paused())
  end)

  it("does not keep a deleted player in the network", function()
    local player_table = a_player(1)
    local nwd = with_history(arrive(player_table, a_network(1)))

    -- on_player_removed clears storage.players before telling us about it
    storage.players[1] = nil
    network_data.remove_player_index(1)

    assert.are.equal(0, network_data.players_in_network(nwd))
    assert.is_not_nil(nwd.unobserved_since)
  end)

  it("does not push the grace period out when a player logs out twice", function()
    local player_table = a_player(1)
    local nwd = arrive(player_table, a_network(1))

    leave(player_table)
    local stamped_at = nwd.unobserved_since
    advance(600)
    network_data.remove_player_index(1) -- Logging out after having already left

    assert.are.equal(stamped_at, nwd.unobserved_since)
  end)
end)
