local bots_gui = {}

local player_data = require("scripts.player-data")
local locations_window = require("scripts.location-gui")

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
    name = "bots_insights_titlebar"
  }
  titlebar.drag_target = window

  titlebar.add {
    type = "label",
    caption = "Logistics insights", -- Could add "[img=item/logistic-robot]""
    style = "frame_title",
    ignored_by_interaction = true
  }

  local dragger = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    height = 24,
    right_margin = 4,
    ignored_by_interaction = true
  }
  dragger.style.horizontally_stretchable = true
  dragger.style.vertically_stretchable = true

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
    name = "logistics-insights-network-id",
  }
  player_table.ui.network.roboports = bots_table.add {
    type = "sprite-button",
    sprite = "entity/roboport",
    style = "slot_button",
    name = "logistics-insights-roboports",
  }
  player_table.ui.network.logistics_bots = bots_table.add {
    type = "sprite-button",
    sprite = "entity/logistic-robot",
    style = "slot_button",
    name = "logistics-insights-logistics_bots",
  }
  player_table.ui.network.requesters = bots_table.add {
    type = "sprite-button",
    sprite = "item/requester-chest",
    style = "slot_button",
    name = "logistics-insights-requesters",
  }
  player_table.ui.network.providers = bots_table.add {
    type = "sprite-button",
    sprite = "item/passive-provider-chest",
    style = "slot_button",
    name = "logistics-insights-providers",
  }
  player_table.ui.network.storages = bots_table.add {
    type = "sprite-button",
    sprite = "item/storage-chest",
    style = "slot_button",
    name = "logistics-insights-storages",
  }
end -- add_network_row

local function add_sorted_item_row(player_table, gui_table, title, titletip, need_progressbar)
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
  if need_progressbar then
    progressbar = cell.add {
      type = "progressbar",
      name = title .. "_progressbar",
    }
    progressbar.style.horizontally_stretchable = true
    player_table.ui[title].progressbar = progressbar
  end

  player_table.ui[title].cells = {}
  for count = 1, player_table.settings.max_items do
    player_table.ui[title].cells[count] = gui_table.add {
      type = "sprite-button",
      style = "slot_button",
      enabled = false,
    }
  end
end

-- Chreate the main table with all the rows needed
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
      "Items currently being delivered, sorted by count",
      true
    )
  end

  if player_table.settings.show_history and storage.delivery_history and not player_table.paused then
    add_sorted_item_row(
      player_table,
      bots_table,
      "Total items",
      "Sum of items delivered by bots in current network, biggest number first",
      false
    )
    -- Total Ticks line not interesting enough to include
    -- add_sorted_item_row(
    --   player_table,
    --   bots_table,
    --   "Total ticks",
    --   "Total time taken to deliver, longest time first",
    --   false
    -- )
    add_sorted_item_row(
      player_table,
      bots_table,
      "Ticks/item",
      "Average time taken to deliver each item, highest average first",
      false
    )
  end

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
  if not progress then
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
      progress.current - 1,
      progress.total,
      ((progress.current - 1) / progress.total) * 100)
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
    -- Restore the previous location, if it exists
    window.location = player_table.window_location
  else
    window.location = { x = 200, y = 0 }
  end
  bots_gui.update(player, player_table)
end

-- Updating the window with live data

-- Display item sprites and numbers in sort order.
local function update_sorted_item_row(player_table, title, all_entries, sort_fn, number_field)
  -- If paused, just disable all the fields
  if player_table.paused then
    for i = 1, player_table.settings.max_items do
      cell = player_table.ui[title].cells[i]
      cell.enabled = false
    end
    return
  end

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
    if number_field == "count" then
      cell.tooltip = string.format("%d %s %s", entry.count, entry.quality_name or "normal", entry.item_name)
    elseif number_field == "ticks" then
      cell.tooltip = string.format("%d ticks\nto deliver %d %s %s", entry.ticks, entry.count,
        entry.quality_name or "normal", entry.item_name)
    elseif number_field == "avg" then
      cell.tooltip = string.format("An average of %.1f ticks\nto deliver %d %s %s", entry.avg, entry.count,
        entry.quality_name or "normal", entry.item_name)
    end
    cell.enabled = true
    count = count + 1
  end

  -- Pad with blank elements
  while count < player_table.settings.max_items do
    cell = player_table.ui[title].cells[count + 1]
    cell.sprite = ""
    cell.tooltip = ""
    cell.number = nil
    cell.enabled = false
    count = count + 1
  end
end -- update_sorted_item_row

local function update_activity_row(player_table)
  local reset_activity_buttons = function(ui_table, sprite, number, tip, disable)
    -- Reset all cells in the ui_table to empty
    for _, cell in pairs(ui_table) do
      if cell and cell.cell.type == "sprite-button" then
        cell = cell.cell -- Get the actual sprite-button
        if sprite then cell.sprite = "" end
        if tip then cell.tooltip = "" end
        if number then cell.number = nil end
        if disable then cell.enabled = false end
      end
    end
  end

  if player_table.network then
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
  else
    reset_activity_buttons(player_table.ui.activity.cells, false, true, true, false)
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
    end
  end

  local reset_network_buttons = function(ui_table, sprite, number, tip, disable)
    -- Reset all cells in the ui_table to empty
    for _, cell in pairs(ui_table) do
      if cell and cell.type == "sprite-button" then
        if sprite then cell.sprite = "" end
        if tip then cell.tooltip = "" end
        if number then cell.number = nil end
        if disable then cell.enabled = false end
      end
    end
  end

  if player_table.network then
    update_element(player_table.ui.network.id, player_table.network.network_id,
      "Network ID 1", "Network ID %d")
    update_element(player_table.ui.network.roboports, table_size(player_table.network.cells),
      "1 roboport in network", "%d roboports in network")
    player_table.ui.network.roboports.tags = { follow = false }

    update_element(player_table.ui.network.logistics_bots, player_table.network.all_logistic_robots,
      "1 logistics bot in network", "%d logistics bots in network")
    player_table.ui.network.logistics_bots.tags = { follow = true }

    update_element(player_table.ui.network.requesters, table_size(player_table.network.requesters),
      "1 requester in network (Chests, Silos, etc)", "%d requesters in network (Chests, Silos, etc)")
    player_table.ui.network.requesters.tags = { follow = false }
    update_element(player_table.ui.network.providers,
      table_size(player_table.network.providers) - table_size(player_table.network.cells),
      "1 provider in network, plus roboports", "%d providers in network, plus roboports")
    update_element(player_table.ui.network.storages, table_size(player_table.network.storages),
      "1 storage chest in network", "%d storage chests in network")
  else
    update_element(player_table.ui.network.id, 0, "No logistics network")
    reset_network_buttons(player_table.ui.network, false, true, true, false)
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
  if player_table.settings.show_history and storage.delivery_history then
    update_sorted_item_row(
      player_table,
      "Total items",
      storage.delivery_history,
      function(a, b) return a.count > b.count end,
      "count"
    )
    -- update_sorted_item_row(
    --   player_table,
    --   "Total ticks",
    --   storage.delivery_history,
    --   function(a, b) return a.ticks > b.ticks end,
    --   "ticks"
    -- )
    update_sorted_item_row(
      player_table,
      "Ticks/item",
      storage.delivery_history,
      function(a, b) return a.avg > b.avg end,
      "avg"
    )
  end
  update_activity_row(player_table)
  update_network_row(player_table)

  -- local in_train_gui = player.opened_gui_type == defines.gui_type.entity and player.opened.type == "locomotive"
  -- window = player.gui.screen.logistics_insights_window
  -- if window then
  --   window.visible = not in_train_gui
  -- end
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

local function get_random(list)
  if list and #list ~= table_size(list) then
    assert(false, "Need to use table_size!")
  end
  if not list or #list == 0 then
    return nil
  end
  local index = math.random(1, #list)
  return list[index]
end

---@param player LuaPlayer
---@param player_data
---@param element LuaGuiElement sprite-button
---@param mouse_button defines.mouse_button_type
function bots_gui.open_location_on_map(player, player_data, element, mouse_button)
  local instructions = element.tags --[[@as ClickInstructions]]
  follow = false
  if element.name == "logistics-insights-roboports" then
    item = get_random(player_data.network.cells)
    if item then
      item = item.owner
    end
  elseif element.name == "logistics-insights-requesters" then
    item = get_random(player_data.network.requesters)
  elseif element.name == "logistics-insights-logistics_bots" then
    item = get_random(player_data.network.logistic_robots)
    follow = true
  else
    item = nil
  end
  if item == nil then
    return
  end

  if mouse_button == defines.mouse_button_type.left then
    ResultLocation.open(player, item, follow)
  end
end

-- ONCLICK

function bots_gui.onclick(event)
  if string.sub(event.element.name, 1, 18) == "logistics-insights" then
    local player = game.get_player(event.player_index)
    local player_table = storage.players[event.player_index]
    if event.element.name == "logistics-insights-clear-history" then
      storage.delivery_history = {}
      bots_gui.update(player, player_table)
    elseif event.element.name == "logistics-insights-pause" then
      -- Start/stop gathering insights
      player_table.paused = not player_table.paused or false
      update_gathering_data(player_table.paused, event.element)
      bots_gui.update(player, player_table)
    elseif event.element.tags then
      -- locations_window.create(player, storage.players[event.player_index])
      if player then
        bots_gui.open_location_on_map(player, player_table, event.element, event.button)
      end
    end
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
