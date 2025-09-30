-- Handle changes in configuration and migrations for Logistics Insights mod
local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local TickCounter = require("scripts.tick-counter")
local main_window = require("scripts.mainwin.main_window")
local networks_window = require("scripts.networkswin.networks_window")
local controller_gui = require("scripts.controller-gui")
local chunker = require("scripts.chunker")
local scheduler = require("scripts.scheduler")
local suggestions = require("scripts.suggestions")
local logistic_cell_counter = require("scripts.logistic-cell-counter")
local bot_counter = require("scripts.bot-counter")
local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local json = require("scripts.json")

local function init_storage_and_settings()
  player_data.init_storages()
end

local function reinitialise_ui(player, player_table)
  if player and player_table then
    player_table.ui = nil -- Reset UI to force recreation
    controller_gui.create_window(player)
    main_window.ensure_ui_consistency(player, player_table)
    networks_window.create(player)
  else
    -- If we can't get the player or table, just re-initialise storage and settings
    init_storage_and_settings()
  end
end

-- All migrations. MUST BE SORTED BY VERSION NUMBER!
local li_migrations = {
  ["0.9.7"] = function()
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player_table and player_table.ui then
        -- Initialise new paused_items table
        ---@diagnostic disable-next-line: inject-field
        player_table.saved_paused_state = nil -- Remove old saved paused state

        -- Set new settings
        player_table.settings.show_undersupply = true -- Enable undersupply by default
        player_table.settings.show_suggestions = true -- Enable suggestions by default
      end
    end
  end,

  ["0.9.8"] = function()
    storage.global = {}
    -- Initialise new per-network storage
    network_data.init()
    -- Move all of the things that used to be global to per-player
    for player_index, player_table in pairs(storage.players) do
      -- Removed fields
      ---@diagnostic disable-next-line: inject-field
      player_table.bots_table = nil
      ---@diagnostic disable-next-line: inject-field
      player_table.current_activity_interval = nil
      ---@diagnostic disable-next-line: inject-field
      player_table.current_activity_size = nil
      ---@diagnostic disable-next-line: inject-field
      player_table.undersupply_paused = nil
      -- Ensure network data exists
      network_data.create_networkdata(player_table.network)
    end
    -- Remove all of the old global storages
    storage.bot_items = nil
    storage.delivery_history = nil
    storage.bot_active_deliveries = nil
    storage.bot_deliveries = nil
    storage.last_pass_bots_seen = nil
    storage.idle_bot_qualities = nil
    storage.roboport_qualities = nil
    storage.picking_bot_qualities = nil
    storage.delivering_bot_qualities = nil
    storage.charging_bot_qualities = nil
    storage.waiting_bot_qualities = nil
    storage.other_bot_qualities = nil
    storage.bot_delivery_lookup = nil
    storage.total_bot_qualities = nil
  end,

  ["0.9.10"] = function() -- Add new scheduler
    -- Initialise scheduler and player overrides on schedules
    for _, player_table in pairs(storage.players) do
      player_table.schedule_last_run = {}
      -- Clear legacy paused list contents
      ---@diagnostic disable-next-line: inject-field
      player_table.paused_items = nil
    end
    -- Apply player-defined intervals to scheduled tasks
    scheduler.apply_all_player_intervals()
  end,

  ["0.10.1"] = function() -- Add new networks window, move many things from player to network
    -- Destroy the controller window so it can be recreated with the new layout
    for player_index, _ in pairs(storage.players) do
      local player = game.get_player(player_index)
      -- local gui = player.gui.top.logistics_insights_mini
      if player and player.valid and player.gui.top.logistics_insights_mini then
        player.gui.top.logistics_insights_mini.destroy()
      end
    end

    -- Transfer suggestions from player data to network data for active network and initialise the rest
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      local pt_sugg = player_table.suggestions
      -- Iterate over all networks we're scanning
      for nwid, nwdata in pairs(storage.networks) do
        if player and player.valid and player_table.network and player_table.network.valid then
          if nwid == player_table.network.network_id then
            -- Transfer suggestions to network data
            nwdata.suggestions = pt_sugg
          else
            nwdata.suggestions = suggestions.new()
          end
          ---@diagnostic disable-next-line: inject-field
          player_table.suggestions = nil
        end
      end
    end

    -- Initialise players and add new fields to networks
    for _, storage_nw in pairs(storage.networks) do
      storage_nw.players_set = {}
      storage_nw.bot_chunker = chunker.new()
      storage_nw.cell_chunker = chunker.new()
    end
    for _, player in pairs(game.connected_players) do
      local player_table = player_data.get_player_table(player.index)
      if player_table and player_table.network then
        network_data.player_changed_networks(player_table, nil, player_table.network)
      end
    end

    -- Remove any networks that are not observed, if the setting is set that way
    network_data.purge_unobserved_networks()

    -- Transfer old per-player settings to new global settings
    local got_settings = false
    for _, player_table in pairs(storage.players) do
      if player_table and player_table.settings then
        -- Set the new global settings
        if not got_settings then
          settings.global["li-chunk-size-global"] = {value = player_table.settings.chunk_size or 400}
          settings.global["li-chunk-processing-interval-ticks"] = {value = 3} -- New setting, default to 3 ticks
          settings.global["li-gather-quality-data-global"] = {value = player_table.settings.gather_quality_data or true}
          got_settings = true -- Only do this for the first player, who hopefully was the host
        end
        -- Remove old settings
        player_table.settings.chunk_size = nil
        player_table.settings.bot_chunk_interval = nil
        player_table.settings.gather_quality_data = nil

        ---@diagnostic disable-next-line: inject-field
        player_table.bot_chunker = nil
        ---@diagnostic disable-next-line: inject-field
        player_table.cell_chunker = nil
      end
    end

    -- Add surface and force name to every network without one. Brute force!
    for _, storage_nw in pairs(storage.networks) do
      local nwid = storage_nw.id
      for _, force in pairs(game.forces) do
        for surface, networks in pairs(force.logistic_networks) do
          for _, network in pairs(networks) do
            if network.network_id == nwid then
              storage_nw.surface = surface or ""
              storage_nw.force_name = force.name or ""
              goto network_found
            end
          end
        end
      end
      storage.networks[nwid] = nil -- Remove networks we can't find
      ::network_found::
    end
  end,

  ["0.10.2"] = function() -- History timer to network, players as set
    -- Convert LINetworkData.players from array-style to set-style (keys are player indices, value=true)
    if not storage.networks then return end
    for _, nwd in pairs(storage.networks) do
      ---@diagnostic disable-next-line: undefined-field
      local players = nwd.players -- Old field name
      if players == nil then
        nwd.players_set = {}
      else
        local newset = {}
        for k, player_index in pairs(players) do
          newset[player_index] = true
        end
        nwd.players_set = newset
      end
      ---@diagnostic disable-next-line: undefined-field, inject-field
      nwd.players = nil -- Remove old field
    end

    -- Get rid of old per-player history_timer and move to per-network history_timer
    for _, player_table in pairs(storage.players) do
      if player_table then
        ---@diagnostic disable-next-line: undefined-field, inject-field
        player_table.history_timer = nil -- Remove old field
      end
    end
    -- Make sure all networks have a history timer, unpaused, and that histories are cleared
    -- Sad, but necessary for this transition to work
    for _, nwd in pairs(storage.networks) do
      -- Initialise fields that may be missing
      if not nwd.history_timer then
        nwd.history_timer = TickCounter.new()
      end
      if not nwd.suggestions then
        nwd.suggestions = suggestions.new()
      end
      nwd.history_timer:reset() -- Ensure unpaused
      nwd.delivery_history = {} -- Clear history
    end
  end,

  ["0.10.3"] = function() -- Remove or globalise settings
    for player_index, player_table in pairs(storage.players) do
      if player_table and player_table.settings then
        player_table.settings.pause_for_bots = nil -- Remove old setting
      end
    end
  end,

  ["0.10.4"] = function() -- Optimise UI updates and counting for large networks
    -- Restart cell counting, since we added a new field and optimised the chunker logic
    for _, nwd in pairs(storage.networks) do
      nwd.total_cells = 0
      logistic_cell_counter.restart_counting(nwd)
      bot_counter.restart_counting(nwd)
    end
  end,

  ["0.10.5"] = function() -- Spread out undersupply calculation over multiple ticks
    storage.analysing_networkdata = nil -- New field, make sure it's clear
    -- Add new fields and remove deprecated field
    for _, nwd in pairs(storage.networks) do
      nwd.last_scanned_tick = nwd.last_active_tick or 0
      nwd.last_analysed_tick = 0
      ---@diagnostic disable-next-line: inject-field
      nwd.last_active_tick = nil
    end
  end,

  ["0.10.6"] = function() -- Cache per-map settings properly
    global_data.init()
    -- Make sure the players' networks are registered correctly
    for _, player in pairs(game.connected_players) do
      local player_table = player_data.get_player_table(player.index)
      if player_table and player_table.network then
        local nwd = network_data.create_networkdata(player_table.network)
        if nwd then
          nwd.players_set[player_table.player_index] = true
        end
      end
    end
  end,

  ["0.10.8"] = function()
    -- Removed progress indicators and pause buttons, so make sure UIs are reinitialised
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      ---@diagnostic disable-next-line: inject-field
      player_table.capabilities = nil -- Deprecated field
      -- Hide Networks window by default
      player_table.networks_window_visible = false
    end
  end,

  ["0.10.11"] = function()
    -- Changed progress bars to single label showing %
  end,

  ["0.11.0"] = function()
    -- Initialise new per-network settings
    for _, nwd in pairs(storage.networks) do
      nwd.ignored_storages_for_mismatch = {}
      nwd.ignore_higher_quality_mismatches = false
      nwd.ignored_items_for_undersupply = {}
    end

    -- Initialise new per-player setting
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      player_table.settings_network_id = nil
    end
  end,

  ["0.11.1"] = function()
    ---@param achunker Chunker
    local function migrate_chunker(achunker)
      if achunker then
        if achunker.networkdata then
          achunker.network_id = achunker.networkdata.id
        else
          achunker.network_id = 0
        end
        ---@diagnostic disable-next-line: inject-field
        achunker.networkdata = nil
      end
    end

    local function remove_localised_strings(table)
      for _, item_record in pairs(table) do
        if item_record then
          item_record.localised_name = nil
          item_record.localised_quality_name = nil
        end
      end
    end

    -- Chunkers do not belong in the player table
    for player_index, player_table in pairs(storage.players) do
      ---@diagnostic disable-next-line: inject-field
      player_table.bot_chunker = nil
      ---@diagnostic disable-next-line: inject-field
      player_table.cell_chunker = nil
    end

    -- No longer store the networkdata in the chunkers, causes recursion during save!
    for _, nwd in pairs(storage.networks) do
      migrate_chunker(nwd.cell_chunker)
      migrate_chunker(nwd.bot_chunker)
      network_data.prune_old_data(nwd, true)
    end
    local state = storage.analysis_state
    if state then
      migrate_chunker(state.storage_chunker)
      migrate_chunker(state.undersupply_chunker)
    end

    -- Remove localised names from item records to save space and time
    for _, nwd in pairs(storage.networks) do
      remove_localised_strings(nwd.bot_deliveries)
      remove_localised_strings(nwd.bot_active_deliveries)
      remove_localised_strings(nwd.delivery_history)

      ---@diagnostic disable-next-line: inject-field
      nwd.last_accessed_tick = nil -- Remove obsolete field
    end
  end,

  ["0.11.3"] = function()
    -- Added per-network setting to ignore buffer chests for undersupply calculations
    for _, nwd in pairs(storage.networks) do
      nwd.ignore_buffer_chests_for_undersupply = false
    end

    -- Added new per-network setting, so reinitialise UIs
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      reinitialise_ui(player, player_table)
    end
  end,

  ["0.11.4"] = function()
    -- Added new button to per-network settings
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      reinitialise_ui(player, player_table)
    end
  end,
}

return li_migrations
