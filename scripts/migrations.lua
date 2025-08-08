-- Handle changes in configuration and migrations for Logistics Insights mod
local player_data = require("scripts.player-data")
local TickCounter = require("scripts.tick-counter")
local main_window = require("scripts.mainwin.main_window")
local suggestions = require("scripts.suggestions")
local undersupply_row = require("scripts.mainwin.undersupply_row")
local suggestions_row = require("scripts.mainwin.suggestions_row")

local function init_storage_and_settings()
  player_data.init_storages()
end

local function reinitialise_ui()
  local player = player_data.get_singleplayer_player()
  local player_table = player_data.get_singleplayer_table()
  if player and player_table then
    player_table.ui = nil -- Reset UI to force recreation
    main_window.ensure_ui_consistency(player, player_table)
  else
    -- If we can't get the player or table, just re-initialise storage and settings
    init_storage_and_settings()
  end
end

local li_migrations = {
  ["0.9.7"] = function()
    local player_table = player_data.get_singleplayer_table()
    if player_table and player_table.ui and player_table.bots_table then
      -- Initialise new paused_items table
      player_table.paused_items = {}
      ---@diagnostic disable-next-line: inject-field
      player_table.saved_paused_state = nil -- Remove old saved paused state
      
      -- Initialise the new suggestions table
      player_table.suggestions = suggestions.new()
      -- Set new settings
      player_table.settings.show_undersupply = true -- Enable undersupply by default
      player_table.settings.show_suggestions = true -- Enable suggestions by default
    end
    -- Re-initialise the UI as buttons have moved around since last version
    reinitialise_ui()
  end,

  ["0.8.3"] = function()
    -- Changed the UI layout, so re-initialise it
    reinitialise_ui()
  end,

  ["0.8.5"] = function()
    -- Added bot chunk settings, set defaults
    local player_table = player_data.get_singleplayer_table()
    if player_table then
      player_table.settings.bot_chunk_interval = 10
    end

    -- Added tags to certain cells to control tooltips, so re-generate the UI
    reinitialise_ui()
  end,

  ["0.8.9"] = function()
    -- Initialize the new History Timer object
    local player_table = player_data.get_singleplayer_table()
    if player_table then
      player_table.history_timer = TickCounter.new()
      -- The paused state is now contained within the history timer
      ---@diagnostic disable-next-line: undefined-field
      if player_table.paused then
      player_table.history_timer:pause()
      end
      ---@diagnostic disable-next-line: inject-field
      player_table.paused = nil -- Remove old paused state
    end
  end,

  ["0.9.0"] = function()
    -- Set the new mini window toggle setting to its default
    local player_table = player_data.get_singleplayer_table()
    if player_table and player_table.settings then
      player_table.settings.show_mini_window = true
    end
  end,

  ["0.9.3"] = function()
    -- TickCounter now registers the metatable so this isn't needed on_load anymore
    -- Go through all player data and restore any TickCounter objects
    for _, player_table in pairs(storage.players) do
      if player_table then
        local counter = player_table.history_timer
        if counter and type(counter) == "table" then
        -- Check if this looks like a TickCounter object
        if counter.start_tick and counter.paused ~= nil then
          -- Reconnect the metatable
          setmetatable(counter, TickCounter)
          end
        end
      end
    end

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
    local player_table = player_data.get_singleplayer_table()
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
    reinitialise_ui()
  end,
 
  ["0.9.6"] = function()
    -- Rename the private fields in TickCounter references
    for _, player_table in pairs(storage.players) do
      if player_table and player_table.history_timer then
        local counter = player_table.history_timer
        if type(counter) == "table" then
          -- Rename the fields to match the new TickCounter structure
          counter._start_tick = counter.start_tick or game.tick
          counter._paused = counter.paused or false
          counter._pause_tick = counter.pause_tick or nil
          counter._accumulated_time = counter.accumulated_time or 0
          -- Remove the old fields
          counter.start_tick = nil
          counter.paused = nil
          counter.pause_tick = nil
          counter.accumulated_time = nil
        end
      end
    end

    -- Re-initialise the UI to use the new Activity row tooltips
    reinitialise_ui()
  end,
}

return li_migrations
