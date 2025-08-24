-- Handle changes in configuration and migrations for Logistics Insights mod
local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local TickCounter = require("scripts.tick-counter")
local main_window = require("scripts.mainwin.main_window")
local chunker = require("scripts.chunker")
local scheduler = require("scripts.scheduler")
local capability_manager = require("scripts.capability-manager")
local suggestions = require("scripts.suggestions")
local suggestions = require("scripts.suggestions")

local function init_storage_and_settings()
  player_data.init_storages()
end

local function reinitialise_ui(player, player_table)
  if player and player_table then
    player_table.ui = nil -- Reset UI to force recreation
    main_window.ensure_ui_consistency(player, player_table)
  else
    -- If we can't get the player or table, just re-initialise storage and settings
    init_storage_and_settings()
  end
end

-- All migrations. MUST BE SORTED BY VERSION NUMBER!
local li_migrations = {
  ["0.8.3"] = function()
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      -- Changed the UI layout, so re-initialise it
      reinitialise_ui(player, player_table)
    end
  end,

  ["0.8.5"] = function()
    -- Added bot chunk settings, set defaults
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player_table then
        player_table.settings.bot_chunk_interval = 10
      end

      -- Added tags to certain cells to control tooltips, so re-generate the UI
      reinitialise_ui(player, player_table)
    end
  end,
  ["0.8.9"] = function()
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      -- Initialize the new History Timer object (Deprecated in 0.10)
      -- Initialize the new History Timer object (Deprecated in 0.10)
      if player_table then
        ---@diagnostic disable-next-line: inject-field
        player_table.paused = nil -- Remove old paused state
      end
    end
  end,

  ["0.9.0"] = function()
    -- Set the new mini window toggle setting to its default
    for _, player_table in pairs(storage.players) do
      if player_table and player_table.settings then
        player_table.settings.show_mini_window = true
      end
    end
  end,

  ["0.9.3"] = function()
    -- TickCounter now registers the metatable so this isn't needed on_load anymore
    -- Go through all player data and restore any TickCounter objects
    -- (Deprecated in 0.10)
    -- (Deprecated in 0.10)

    local function add_localised_names_to(list)
      for key, entry in pairs(list) do
        if entry.item_name and entry.quality_name then
          if prototypes.item[entry.item_name] then
            entry.localised_name = prototypes.item[entry.item_name].localised_name
          elseif prototypes.entity[entry.item_name] then
            entry.localised_name = prototypes.entity[entry.item_name].localised_name
          end
          entry.localised_quality_name = prototypes.quality[entry.quality_name].localised_name
        end
      end
    end

    -- Stored state now needs to hold localised names too
    add_localised_names_to(storage.delivery_history)
    add_localised_names_to(storage.bot_active_deliveries)
    add_localised_names_to(storage.bot_deliveries)
  end,

  ["0.9.5"] = function()
    -- Add "gather quality" setting"
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player_table and player_table.settings then
        player_table.settings.gather_quality_data = true
      end

      -- Ensure new qualities storage exists
      storage.idle_bot_qualities = storage.idle_bot_qualities or {}
      storage.roboport_qualities = storage.roboport_qualities or {}
      storage.picking_bot_qualities = storage.picking_bot_qualities or {}
      storage.delivering_bot_qualities = storage.delivering_bot_qualities or {}
      storage.charging_bot_qualities = storage.charging_bot_qualities or {}
      storage.waiting_bot_qualities = storage.waiting_bot_qualities or {}
      storage.other_bot_qualities = storage.other_bot_qualities or {}

      -- Re-initialise the UI to make sure the new quality_table fields are set
      reinitialise_ui(player, player_table)
    end
  end,

  ["0.9.6"] = function()
    -- Rename the private fields in TickCounter references
    -- (Deprecated in 0.10)
    -- (Deprecated in 0.10)
    for player_index, player_table in pairs(storage.players) do
      -- Re-initialise the UI to use the new Activity row tooltips
      local player = game.get_player(player_index)
      reinitialise_ui(player, player_table)
    end
  end,

  ["0.9.7"] = function()
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player_table and player_table.ui then
        -- Initialise new paused_items table
        ---@diagnostic disable-next-line: inject-field
        player_table.paused_items = {}
        ---@diagnostic disable-next-line: inject-field
        player_table.saved_paused_state = nil -- Remove old saved paused state
        
        -- Initialise the suggestions table (from 0.9.12, deprecated)
        ---@diagnostic disable-next-line: inject-field
        -- Initialise the suggestions table (from 0.9.12, deprecated)
        ---@diagnostic disable-next-line: inject-field
        player_table.suggestions = suggestions.new()
        -- Set new settings
        player_table.settings.show_undersupply = true -- Enable undersupply by default
        player_table.settings.show_suggestions = true -- Enable suggestions by default
      end
      -- Re-initialise the UI as buttons have moved around since last version
      reinitialise_ui(player, player_table)
    end
  end,

  ["0.9.8"] = function()
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
      -- Create persistent chunkers (deprecated)
      --player_table.bot_chunker = chunker.new(player_table)
      --player_table.cell_chunker = chunker.new(player_table)
      -- Create persistent chunkers (deprecated)
      --player_table.bot_chunker = chunker.new(player_table)
      --player_table.cell_chunker = chunker.new(player_table)
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
      -- Ensure capabilities structure exists
      if not player_table.capabilities then
        capability_manager.init_player(player_table)
      end
      -- Translate legacy paused_items into capability user reasons
      local paused = player_table.paused_items
      if paused and #paused > 0 then
        for _, name in ipairs(paused) do
          capability_manager.set_reason(player_table, name, "user", true)
        end
      end
      -- Ensure dirty flags cleared but retain capability records
      if player_table.capabilities then
        for _, rec in pairs(player_table.capabilities) do
          rec.dirty = false
        end
      end
      -- Clear legacy paused list contents
      ---@diagnostic disable-next-line: inject-field
      player_table.paused_items = nil
    end
    -- Apply player-defined intervals to scheduled tasks
    scheduler.apply_all_player_intervals()
  end,

  ["0.9.11"] = function()
    -- Fix an issue in the paused state
    for _, player_table in pairs(storage.players) do
      if player_table and player_table.history_timer then
        if not player_table.settings.pause_while_hidden then
          -- Don't say analysis is paused because the window is hidden if the setting is false
          capability_manager.set_reason(player_table, "window", "user", false)
        end
        -- Ensure the UI is consistent with the paused state
        main_window.refresh_mini_button_enabled_states(player_table)
      end
    end
  end,

  ["0.10.1"] = function() -- Add new networks window
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
          settings.global["li-chunk-size-global"] = {value = player_table.settings.chunk_size}
          settings.global["li-chunk-processing-interval-ticks"] = {value = player_table.settings.bot_chunk_interval}
          settings.global["li-gather-quality-data-global"] = {value = player_table.settings.gather_quality_data}
          got_settings = true -- Only do this for the first player, who hopefully was the host
        end
        -- Remove old settings
        player_table.settings.chunk_size = nil
        player_table.settings.bot_chunk_interval = nil
        player_table.settings.gather_quality_data = nil
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

  ["0.10.2"] = function()
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
        -- Ensure the window does not appear to be hidden
        capability_manager.set_reason(player_table, "window", "hidden", false)
      end
    end
    -- Make sure all networks have a history timer, unpaused, and that histories are cleared
    -- Sad, but necessary for this transition to work
    for _, nwd in pairs(storage.networks) do
      if not nwd.history_timer then
        nwd.history_timer = TickCounter.new()
      end
      nwd.history_timer:reset() -- Ensure unpaused
      nwd.delivery_history = {} -- Clear history
      nwd.bg_paused = false -- New field to track if background scanning is paused
    end
  end,
}

return li_migrations
