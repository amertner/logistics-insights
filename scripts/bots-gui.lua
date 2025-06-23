local bots_gui = {}

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
      name = "bot-insight-clear-history"
    }
  end
end

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
    visible = player.controller_type ~= defines.controllers.cutscene,
  }

  add_titlebar(window, player_table)
  local bots_table = window.add {
    type = "table",
    name = "bots_table",
    column_count = player_table.settings.max_items + 1
  }
  player_table.bots_windows = window
  player_table.bots_table = bots_table
  if player_table.window_location then
      window.location = player_table.window_location
  else
    window.auto_center = true
  end
  bots_gui.update(player, player_table)
end

-- Replace any character not allowed with an underscore
local function sanitize_entity_name(str)
  -- Convert to lowercase, replace invalid chars with "_"
  return string.gsub(string.lower(str), "[^a-z0-9_-]", "_")
end

-- Adds table GUI element displaying item sprites and numbers in sort order.
local function add_sorted_item_table(title, gui_table, all_entries, sort_fn, number_field, max_items, paused, titletip)
  -- Collect entries into an array
  local sorted_entries = {}
  for index, entry in pairs(all_entries) do
    table.insert(sorted_entries, entry)
  end

  -- Sort using the provided function
  table.sort(sorted_entries, sort_fn)

  local table_row = gui_table.add {
    type = "label",
    caption = title,
    style = "heading_2_label",
    tooltip = titletip,
  }

  -- Add up to max_items entries
  local count = 0
  for _, entry in ipairs(sorted_entries) do
    if count >= max_items then break end
    gui_table.add {
      type = "sprite-button",
      sprite = "item/" .. entry.item_name,
      style = "slot_button",
      quality = entry.quality_name or "normal",
      number = entry[number_field],
      name = "bot-insight-test-" .. sanitize_entity_name(title) .. count,
      tooltip = string.format("Items: %d", entry.count),
      enabled = not paused
    }
    count = count + 1
  end

  -- Pad with blank elements if needed
  while count < max_items do
    gui_table.add {
      type = "sprite-button",
      style = "slot_button",
      name = "bot-insight-test-" .. sanitize_entity_name(title) .. count,
      enabled = false,
    }
    count = count + 1
  end
  return table_row
end -- add_sorted_item_table

local function add_bot_activity_row(window, max_items, paused)
  -- Add robot activity stats row
  local activity_icons = {
    { sprite = "entity/logistic-robot",                   key = "logistic-robot-total",           tooltip = "Total robots", onwithpause = true },
    { sprite = "virtual-signal/signal-battery-full",      key = "logistic-robot-available",       tooltip = "Available robots", onwithpause = true },
    { sprite = "virtual-signal/signal-battery-mid-level", key = "charging-robot",                 tooltip = "Robots charging", onwithpause = true },
    { sprite = "virtual-signal/signal-battery-low",       key = "waiting-for-charge-robot",       tooltip = "Robots waiting to charge", onwithpause = true },
    { sprite = "virtual-signal/signal-input",             key = defines.robot_order_type.pickup,  tooltip = "Robots picking up items", onwithpause = false },
    { sprite = "virtual-signal/signal-output",            key = defines.robot_order_type.deliver, tooltip = "Robots delivering items", onwithpause = false },
  }

  if window.bots_activity_row then
    window.bots_activity_row.destroy()
  end

  local activity_row = window.add {
    type = "label",
    caption = "Activity",
    style = "heading_2_label",
    name = "bots_activity_row",
    tooltip = "What are the bots doing right now?",
  }

  for i, icon in ipairs(activity_icons) do
    window.add {
      type = "sprite-button",
      sprite = icon.sprite,
      style = "slot_button",
      tooltip = icon.tooltip,
      name = "bot-insight-activity-" .. i,
      enabled = icon.onwithpause or not paused,
      number = storage.bot_items[icon.key] or 0
    }
  end

  -- Pad with blank elements if needed
  count = #activity_icons
  while count < max_items do
    window.add {
      type = "empty-widget",
    }
    count = count + 1
  end
  return activity_row
end -- add_bot_activity_row

local function add_network_row(bots_table, player_table)
  if player_table.network then
    bots_table.add {
      type = "label",
      caption = "Network",
      style = "heading_2_label",
      tooltip = "Data about the current logistic network",
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "virtual-signal/signal-L",
      number = player_table.network.network_id,
      style = "slot_button",
      tooltip = "Network ID",
      name = "bot-insight-test-network-id",
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "entity/roboport",
      style = "slot_button",
      tooltip = "Number of roboports in network",
      number = table_size(player_table.network.cells),
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "entity/logistic-robot",
      style = "slot_button",
      tooltip = "Number of logistics bots in network",
      number = player_table.network.all_logistic_robots,
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "item/requester-chest",
      style = "slot_button",
      tooltip = "Number of requesters in network (Chests, Silos, etc)",
      number = table_size(player_table.network.requesters),
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "item/passive-provider-chest",
      style = "slot_button",
      tooltip = "Number of providers in network, except roboports)",
      number = table_size(player_table.network.providers) - table_size(player_table.network.cells),
    }
    bots_table.add {
      type = "sprite-button",
      sprite = "item/storage-chest",
      style = "slot_button",
      tooltip = "Number of storage chests in network",
      number = table_size(player_table.network.storages),
    }
  else
    bots_table.add {
      type = "sprite-button",
      sprite = "virtual-signal/signal-L",
      style = "slot_button",
      tooltip = "No network in range",
      name = "bot-insight-test-network-id",
    }
  end
end -- add_network_row

function bots_gui.update(player, player_table)
  if not player_table or player_table.bots_window_visible == false then
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

  if player_table.settings.show_delivering and not player_table.settings.paused then
    local deliveries_table = add_sorted_item_table(
      "Deliveries",
      bots_table,
      storage.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count",
      player_table.settings.max_items,
      player_table.settings.paused,
      "Items currently being delivered, sorted by count"
    )
  end

  -- Show history data
  if player_table.settings.show_history and storage.delivery_history and not player_table.settings.paused then
    local history_row = add_sorted_item_table(
      "Total items",
      bots_table,
      storage.delivery_history,
      function(a, b) return a.count > b.count end,
      "count",
      player_table.settings.max_items,
      player_table.settings.paused,
      "Sum of items delivered by bots in current network, biggest number first"
    )
    local ticks_row = add_sorted_item_table(
      "Total ticks",
      bots_table,
      storage.delivery_history,
      function(a, b) return a.ticks > b.ticks end,
      "ticks",
      player_table.settings.max_items,
      player_table.settings.paused
      "Total time taken to deliver, longest time first"
    )
    local ticksperitem_row = add_sorted_item_table(
      "Ticks/item",
      bots_table,
      storage.delivery_history,
      function(a, b) return a.avg > b.avg end,
      "avg",
      player_table.settings.max_items,
      player_table.settings.paused,
      "Average time taken to deliver each item, highest average first"
    )
  end

  if player_table.settings.show_activity then
    add_bot_activity_row(bots_table, player_table.settings.max_items, player_table.settings.paused)
  end

  -- Show the bot network being inspected
  add_network_row(bots_table, player_table)

  local in_train_gui = player.opened_gui_type == defines.gui_type.entity and player.opened.type == "locomotive"
  window.visible = not in_train_gui
end

local function update_gathering_data(paused, control_element)
  -- Update the gathering state for all players
  for _, player in pairs(game.connected_players) do
    local player_table = storage.players[player.index]
    if player_table then
      player_table.settings.paused = paused or false
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
  if string.sub(event.element.name, 1, 16) == "bot-insight-test" then
    -- Do nothing
  end
  if event.element.name == "bot-insight-clear-history" then
    storage.delivery_history = {}
    local player = game.get_player(event.player_index)
    local player_table = storage.players[event.player_index]
    bots_gui.update(player, player_table)
  elseif event.element.name == "logistics-insights-pause" then
    -- Start/stop gathering insights
    local player = game.get_player(event.player_index)
    local player_table = storage.players[event.player_index]
    player_table.settings.paused = not player_table.settings.paused or false
    update_gathering_data(player_table.settings.paused, event.element)
    bots_gui.update(player, player_table)
  end
end

function bots_gui.destroy(player_table)
  local bots_windows = player_table.bots_windows
  if bots_windows and bots_windows.valid then
    bots_windows.destroy()
    player_table.bots_windows = nil
  end
end

script.on_event(defines.events.on_gui_location_changed, function(event)
    if event.element and event.element.name == "logistics_insights_window" then
        local player_table = storage.players[event.player_index]
        player_table.window_location = event.element.location
    end
end)

return bots_gui
