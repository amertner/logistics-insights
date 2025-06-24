local bots_gui = {}

local player_data = require("scripts.player-data")

function bots_gui.toggle_window_visible(player)
  if not player then
    return
  end
  local player_table = storage.players[player.index]
  player_table.bots_window_visible = not player_table.bots_window_visible

  local gui = player.gui.screen
  if gui.logistics_insights_window then
    gui.logistics_insights_window.visible = player_table.bots_window_visible
  end
end

local function show_deliveries(player_table)
  -- Show deliveries if the setting is enabled or if history is shown
  return player_table.settings.show_delivering or player_table.settings.show_history
end

-- Create UI elements

local function add_titlebar(window, player_table)
  local titlebar = window.add {
    type = "flow",
    direction = "horizontal",
    style_mods = { horizontally_stretchable = true, vertically_align = "center" },
    color = { r = 0, g = 0, b = 0, a = 0.85 }, -- dark, mostly opaque
    name = "bots_insights_titlebar"
  }
  titlebar.drag_target = window

  titlebar.add {
    type = "label",
    caption = "Logistics insights", -- Could add "[img=item/logistic-robot]""
    style = "frame_title",
    ignored_by_interaction = true
  }

  local spacer = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
  }
  spacer.style.horizontally_stretchable = true

  if player_table.settings.show_delivering or player_table.settings.show_history then
    titlebar.add {
      type = "sprite-button",
      sprite = "utility/stop",
      style = "tool_button",
      name = "logistics-insights-pause",
      tooltip = "Pause gathering per-robot data"
    }
  end

  if player_table.settings.show_history then
    titlebar.add {
      type = "sprite-button",
      sprite = "utility/trash",
      style = "tool_button",
      tooltip = "Clear history",
      name = "logistics-insights-clear-history"
    }
  end
end

-- Replace any character not allowed with an underscore
local function sanitize_entity_name(str)
  -- Convert to lowercase, replace invalid chars with "_"
  return string.gsub(string.lower(str), "[^a-z0-9_-]", "_")
end

local function add_bot_activity_row(window, player_table)
  -- Add robot activity stats row
  local activity_icons = {
    { sprite = "entity/logistic-robot",                   key = "logistic-robot-total",           tooltip = "%d total %s",             onwithpause = true },
    { sprite = "virtual-signal/signal-battery-full",      key = "logistic-robot-available",       tooltip = "%d available %s",         onwithpause = true },
    { sprite = "virtual-signal/signal-battery-mid-level", key = "charging-robot",                 tooltip = "%d %s charging",          onwithpause = true },
    { sprite = "virtual-signal/signal-battery-low",       key = "waiting-for-charge-robot",       tooltip = "%d %s waiting to charge", onwithpause = true },
    { sprite = "virtual-signal/signal-input",             key = defines.robot_order_type.pickup,  tooltip = "%d %s picking up items",  onwithpause = false },
    { sprite = "virtual-signal/signal-output",            key = defines.robot_order_type.deliver, tooltip = "%d %s delivering items",  onwithpause = false },
  }

  player_data.register_ui(player_table, "activity")
  local cell = window.add {
    name = "bots_activity_row",
    type = "flow",
    direction = "vertical"
  }
  cell.add {
    type = "label",
    caption = "Activity",
    style = "heading_2_label",
    tooltip = "What are the bots doing right now?",
  }
  progressbar = cell.add {
    type = "progressbar",
    name = "activity_progressbar",
  }
  progressbar.style.horizontally_stretchable = true
  player_table.ui.activity.progressbar = progressbar

  player_table.ui.activity.cells = {}
  for i, icon in ipairs(activity_icons) do
    player_table.ui.activity.cells[icon.key] = {
      tip = icon.tooltip,
      cell = window.add {
        type = "sprite-button",
        sprite = icon.sprite,
        style = "slot_button",
        name = "logistics-insights-activity-" .. i,
        enabled = icon.onwithpause or not player_table.paused,
      }
    }
  end

  -- Pad with blank elements if needed
  count = #activity_icons
  while count < player_table.settings.max_items do
    window.add {
      type = "empty-widget",
    }
    count = count + 1
  end
end -- add_bot_activity_row

local function add_network_row(bots_table, player_table)
  player_data.register_ui(player_table, "network")
  bots_table.add {
    type = "label",
    caption = "Network",
    style = "heading_2_label",
    tooltip = "Data about the current logistic network",
  }
  player_table.ui.network.id = bots_table.add {
    type = "sprite-button",
    sprite = "virtual-signal/signal-L",
    style = "slot_button",
    name = "logistics-insights-test-network-id",
  }
  player_table.ui.network.roboports = bots_table.add {
    type = "sprite-button",
    sprite = "entity/roboport",
    style = "slot_button",
  }
  player_table.ui.network.logistics_bots = bots_table.add {
    type = "sprite-button",
    sprite = "entity/logistic-robot",
    style = "slot_button",
  }
  player_table.ui.network.requesters = bots_table.add {
    type = "sprite-button",
    sprite = "item/requester-chest",
    style = "slot_button",
  }
  player_table.ui.network.providers = bots_table.add {
    type = "sprite-button",
    sprite = "item/passive-provider-chest",
    style = "slot_button",
  }
  player_table.ui.network.storages = bots_table.add {
    type = "sprite-button",
    sprite = "item/storage-chest",
    style = "slot_button",
  }
end -- add_network_row

local function add_sorted_item_row(player_table, gui_table, title, titletip)
  player_data.register_ui(player_table, title)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical"
  }
  cell.add {
    type = "label",
    caption = title,
    style = "heading_2_label",
    tooltip = titletip,
  }
  progressbar = cell.add {
    type = "progressbar",
    name = title .. "_progressbar",
  }
  progressbar.style.horizontally_stretchable = true
  player_table.ui[title].progressbar = progressbar

  player_table.ui[title].cells = {}
  for count = 1, player_table.settings.max_items do
    player_table.ui[title].cells[count] = gui_table.add {
      type = "sprite-button",
      style = "slot_button",
      enabled = false,
    }
  end
end

local function create_bots_table(player, player_table)
  if not player or not player_table then
    return
  end

  window = player.gui.screen.logistics_insights_window
  if not window then
    return -- can't find the window
  end

  local bots_table = player_table.bots_table
  if not bots_table or not bots_table.valid then
    return -- can't find the bots table, something is wrong
  end

  bots_table.clear()

  if show_deliveries(player_table) then
    add_sorted_item_row(
      player_table,
      bots_table,
      "Deliveries",
      "Items currently being delivered, sorted by count"
    )
  end

  -- Show history data
  -- if player_table.settings.show_history and storage.delivery_history and not player_table.paused then
  --   local history_row = add_sorted_item_table(
  --     "Total items",
  --     bots_table,
  --     storage.delivery_history,
  --     function(a, b) return a.count > b.count end,
  --     "count",
  --     player_table.settings.max_items,
  --     player_table.paused,
  --     "Sum of items delivered by bots in current network, biggest number first"
  --   )
  --   local ticks_row = add_sorted_item_table(
  --     "Total ticks",
  --     bots_table,
  --     storage.delivery_history,
  --     function(a, b) return a.ticks > b.ticks end,
  --     "ticks",
  --     player_table.settings.max_items,
  --     player_table.paused,
  --     "Total time taken to deliver, longest time first"
  --   )
  --   local ticksperitem_row = add_sorted_item_table(
  --     "Ticks/item",
  --     bots_table,
  --     storage.delivery_history,
  --     function(a, b) return a.avg > b.avg end,
  --     "avg",
  --     player_table.settings.max_items,
  --     player_table.paused,
  --     "Average time taken to deliver each item, highest average first"
  --   )
  -- end

  if player_table.settings.show_activity then
    add_bot_activity_row(bots_table, player_table)
  end
  add_network_row(bots_table, player_table)
end

local function update_progressbar(progressbar, progress)
  if not progressbar or not progressbar.valid then
    return
  end
  chunk_size = player_data.get_singleplayer_table().settings.chunk_size or 400
  if not progress  then
    progressbar.value = 1
    progressbar.tooltip = string.format("Chunk size %d", chunk_size)
  elseif progress.total == 0 then
    progressbar.value = 1
    progressbar.tooltip = string.format("Chunk size %d", chunk_size)
  else
    progressbar.value = progress.current / progress.total
    progressbar.tooltip = string.format(
      "Chunk size %d\nProcessed %d/%d (%.0f%%)",
      chunk_size,
      progress.current-1,
      progress.total,
      ((progress.current-1) / progress.total) * 100)
  end
end

-- Create main window and all rows needed based on settings
function bots_gui.create_window(player, player_table)
  if player.gui.screen.logistics_insights_window then
    player.gui.screen.logistics_insights_window.destroy()
  end
  local style = "botsgui_frame_style"

  local window = player.gui.screen.add {
    type = "frame",
    name = "logistics_insights_window",
    direction = "vertical",
    style = style,
    visible = player_table.bots_window_visible and player.controller_type ~= defines.controllers.cutscene,
  }

  add_titlebar(window, player_table)
  local bots_table = window.add {
    type = "table",
    name = "bots_table",
    column_count = player_table.settings.max_items + 1
  }
  player_table.bots_table = bots_table
  create_bots_table(player, player_table)
  if player_table.window_location then
    window.location = player_table.window_location
  else
    window.auto_center = true
  end
  bots_gui.update(player, player_table)
end

-- Updating the window with live data

-- Display item sprites and numbers in sort order.
local function update_sorted_item_row(player_table, title, all_entries, sort_fn, number_field)
  -- Collect entries into an array
  local sorted_entries = {}
  for index, entry in pairs(all_entries) do
    table.insert(sorted_entries, entry)
  end

  -- Sort using the provided function
  table.sort(sorted_entries, sort_fn)

  -- Add up to max_items entries
  local count = 0
  for _, entry in ipairs(sorted_entries) do
    if count >= player_table.settings.max_items then break end
    cell = player_table.ui[title].cells[count + 1]
    cell.sprite = "item/" .. entry.item_name
    cell.quality = entry.quality_name or "normal"
    cell.number = entry[number_field]
    cell.tooltip = string.format("%d %s %s", entry.count, entry.quality_name or "normal", entry.item_name)
    cell.enabled = not player_table.paused
    -- name = "logistics-insights-test-" .. sanitize_entity_name(title) .. count,
    count = count + 1
  end

  -- Pad with blank elements
  while count < player_table.settings.max_items do
    cell = player_table.ui[title].cells[count + 1]
    cell.sprite = ""
    cell.caption = ""
    cell.tooltip = ""
    cell.number = 0
    cell.enabled = false
    count = count + 1
  end
end -- update_sorted_item_row

local function update_activity_row(player_table)
  for key, window in pairs(player_table.ui.activity.cells) do
    num = storage.bot_items[key] or 0
    window.cell.number = num
    if num == 1 then
      item = "robot"
    else
      item = "robots"
    end
    window.cell.tooltip = string.format(window.tip, num, item)
  end
end

local function update_network_row(player_table)
  local function update_element(cell, value, tooltip1, tooltip)
    if cell and cell.valid then
      cell.number = value or 0
      if value == 1 or tooltip == nil then
        cell.tooltip = tooltip1
      else
        cell.tooltip = string.format(tooltip, value)
      end
      -- cell.enabled = not player_table.paused
    end
  end

  if player_table.network then
    update_element(player_table.ui.network.id, player_table.network.network_id, 
      "Network ID 1", "Network ID %d")
    update_element(player_table.ui.network.roboports, table_size(player_table.network.cells),
      "1 roboport in network", "%d roboports in network")
    update_element(player_table.ui.network.logistics_bots, player_table.network.all_logistic_robots,
      "1 logistics bot in network", "%d logistics bots in network")
    update_element(player_table.ui.network.requesters, table_size(player_table.network.requesters),
      "1 requester in network (Chests, Silos, etc)", "%d requesters in network (Chests, Silos, etc)")
    update_element(player_table.ui.network.providers,
      table_size(player_table.network.providers) - table_size(player_table.network.cells),
      "1 provider in network, plus roboports", "%d providers in network, plus roboports")
    update_element(player_table.ui.network.storages, table_size(player_table.network.storages),
      "1 storage chest in network", "%d storage chests in network")
  else
    update_element(player_table.ui.network.id, 0, "No logistics network")
    player_table.ui.network.id.number = 0
    player_table.ui.network.roboports.number = 0
    player_table.ui.network.logistics_bots.number = 0
    player_table.ui.network.requesters.number = 0
    player_table.ui.network.providers.number = 0
    player_table.ui.network.storages.number = 0
  end
end -- update_network_row

function bots_gui.update(player, player_table)
  -- Update the bots table with current data, do not recreate it
  if not player or not player.valid or not player_table then
    return -- no player table, can't do anything
  end

  if not player_table.ui then
    return
  end

  if show_deliveries(player_table) then
    update_sorted_item_row(
      player_table,
      "Deliveries",
      storage.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count"
    )
  end

  update_activity_row(player_table)
  update_network_row(player_table)

  local in_train_gui = player.opened_gui_type == defines.gui_type.entity and player.opened.type == "locomotive"
  window.visible = not in_train_gui
end -- update contents

function bots_gui.update_chunk_progress(player_table, chunk_progress)
  if player_table.ui == nil then return end
  update_progressbar(player_table.ui.activity.progressbar, chunk_progress.activity_progress)
  update_progressbar(player_table.ui["Deliveries"].progressbar, chunk_progress.bot_progress)
end

local function update_gathering_data(paused, control_element)
  -- Update the gathering state for all players
  for _, player in pairs(game.connected_players) do
    local player_table = storage.players[player.index]
    if player_table then
      player_table.paused = paused or false
    end
  end
  if paused then
    control_element.sprite = "utility/play"
    control_element.tooltip = "Start gathering per-robot data"
  else
    control_element.sprite = "utility/stop"
    control_element.tooltip = "Pause gathering per-robot data"
  end
end

-- ONCLICK

function bots_gui.onclick(event)
  if string.sub(event.element.name, 1, 16) == "logistics-insights-test" then
    -- Do nothing
  end
  if event.element.name == "logistics-insights-clear-history" then
    storage.delivery_history = {}
    local player = game.get_player(event.player_index)
    local player_table = storage.players[event.player_index]
    bots_gui.update(player, player_table)
  elseif event.element.name == "logistics-insights-pause" then
    -- Start/stop gathering insights
    local player = game.get_player(event.player_index)
    local player_table = storage.players[event.player_index]
    player_table.paused = not player_table.paused or false
    update_gathering_data(player_table.paused, event.element)
    bots_gui.update(player, player_table)
  end
end

function bots_gui.destroy(player, player_table)
  if player.gui.screen.logistics_insights_window then
    player.gui.screen.logistics_insights_window.destroy()
    if player_table.bots_table then
      player_table.bots_table = nil
    end
  end
end

script.on_event(defines.events.on_gui_location_changed, function(event)
  if event.element and event.element.name == "logistics_insights_window" then
    local player_table = storage.players[event.player_index]
    player_table.window_location = event.element.location
  end
end)

return bots_gui
