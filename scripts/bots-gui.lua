local bots_gui = {}

local utils = require("scripts.utils")
local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")
local game_state = require("scripts.game-state")
local tooltips_helper = require("scripts.tooltips-helper")
local ResultLocation = require("scripts.result-location")

-- Cache frequently used functions and constants
local pairs = pairs
local ipairs = ipairs
local table_sort = table.sort
local math_min = math.min
local math_floor = math.floor
local defines_robot_order_type_deliver = defines.robot_order_type.deliver
local defines_robot_order_type_pickup = defines.robot_order_type.pickup

-- Toggle visibility of the main window
function bots_gui.toggle_window_visible(player)
  if not player then
    return
  end
  local player_table = storage.players[player.index]
  player_table.bots_window_visible = not player_table.bots_window_visible
  if player_table.history_timer and player_table.settings.pause_while_hidden then
    if not player_table.bots_window_visible then
      -- History collection pauses when the window is minimized, but remember paused state
      player_table.saved_paused_state = player_table.history_timer:is_paused()
      player_table.history_timer:pause()
    else
      -- Restore prior paused state
      player_table.history_timer:set_paused(player_table.saved_paused_state)
    end
  end

  local gui = player.gui.screen
  if not gui.logistics_insights_window then
    bots_gui.create_window(player, player_table)
  end
  if gui.logistics_insights_window then
    gui.logistics_insights_window.visible = player_table.bots_window_visible
  end
end

-- Make sure all the relevant parts of the UI are available and initialised
function bots_gui.ensure_ui_consistency(player, player_table)
  local gui = player.gui.screen
  if not gui.logistics_insights_window or not player_table.ui then
    bots_gui.create_window(player, player_table)
  end

  local window = gui.logistics_insights_window

  if game_state.needs_buttons() then
    local titlebar = window.bots_insights_titlebar
    if titlebar then
      local unfreeze = titlebar["logistics-insights-unfreeze"]
      local freeze = titlebar["logistics-insights-freeze"]
      game_state.init(unfreeze, freeze)
      game_state.force_update_ui()
    end
  end

  -- Make sure the "Fixed network" toggle is set correctly. 
  -- It cannot be un-set in player_data if the fixed network is deleted
  if window and window.bots_table then
    network_id_cell = window.bots_table["logistics-insights-network-id"]
    if network_id_cell then
      network_id_cell.toggled = player_table.fixed_network
    end
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
    caption = {"mod-name.logistics-insights"},
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

  local unfreeze = titlebar.add {
    type = "sprite-button",
    sprite = "li_play",
    style = "tool_button",
    name = "logistics-insights-unfreeze",
    tooltip = {"bots-gui.unfreeze-game-tooltip"},
  }
  local freeze = titlebar.add {
    type = "sprite-button",
    sprite = "li_pause",
    style = "tool_button",
    name = "logistics-insights-freeze",
    tooltip = {"bots-gui.freeze-game-tooltip"},
  }
  titlebar.add {
    type = "sprite-button",
    sprite = "li_step",
    style = "tool_button",
   name = "logistics-insights-step",
    tooltip = {"bots-gui.step-game-tooltip"},
  }
  game_state.init(unfreeze, freeze)
  game_state.force_update_ui()
end

local function add_bot_activity_row(bots_table, player_table)
  -- Add robot activity stats row
  local activity_icons = {
    { sprite = "entity/logistic-robot",
      key = "logistic-robot-total",
      tip = {"activity-row.robots-total-tooltip"},
      clicktip = true,
      onwithpause = true,
      include_construction = false},
    { sprite = "virtual-signal/signal-battery-full",
      key = "logistic-robot-available",
      tip = {"activity-row.robots-available-tooltip"},
      qualitytable = "idle_bot_qualities",
      clicktip = false,
      onwithpause = false,
      include_construction = false },
    { sprite = "virtual-signal/signal-battery-mid-level",
      key = "charging-robot",
      tip = {"activity-row.robots-charging-tooltip"},
      qualitytable = "charging_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = true },
    { sprite = "virtual-signal/signal-battery-low",
      key = "waiting-for-charge-robot",
      tip = {"activity-row.robots-waiting-tooltip"},
      qualitytable = "waiting_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = true },
    { sprite = "virtual-signal/signal-input",
      key = "picking",
      tip = {"activity-row.robots-picking_up-tooltip"},
      qualitytable = "picking_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = false },
    { sprite = "virtual-signal/signal-output",
      key = "delivering",
      tip = {"activity-row.robots-delivering-tooltip"},
      qualitytable = "delivering_bot_qualities",
      clicktip = true,
      onwithpause = false,
      include_construction = false },
  }

  player_data.register_ui(player_table, "activity")
  local cell = bots_table.add {
    name = "bots_activity_row",
    type = "flow",
    direction = "vertical"
  }
  cell.add {
    type = "label",
    caption = {"activity-row.header"},
    style = "heading_2_label",
    tooltip = {"activity-row.header-tooltip"},
  }
  local progressbar = cell.add {
    type = "progressbar",
    name = "activity_progressbar",
  }
  progressbar.style.horizontally_stretchable = true
  player_table.ui.activity.progressbar = progressbar

  player_table.ui.activity.cells = {}
  for i, icon in ipairs(activity_icons) do
    local cellname = "logistics-insights-" .. icon.key
    player_table.ui.activity.cells[icon.key] = {
      tip = icon.tip,
      onwithpause = icon.onwithpause,
      clicktip = icon.clicktip,
      qualitytable = icon.qualitytable,
      include_construction = icon.include_construction,
      cell = bots_table.add {
        type = "sprite-button",
        sprite = icon.sprite,
        style = "slot_button",
        name = cellname, -- "logistics-insights-activity-" .. i,
        enabled = icon.onwithpause or not player_data.is_paused(player_table),
        tags = { follow = true }
      },
    }
  end

  -- Pad with blank elements if needed
  local count = #activity_icons
  while count < player_table.settings.max_items do
    bots_table.add {
      type = "empty-widget",
    }
    count = count + 1
  end
end -- add_bot_activity_row

local function add_network_row(bots_table, player_table)
  player_data.register_ui(player_table, "network")
  bots_table.add {
    type = "label",
    caption = {"network-row.header"},
    style = "heading_2_label",
    tooltip = {"network-row.header-tooltip"},
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
    tags = { follow = false }
  }
  player_table.ui.network.logistics_bots = bots_table.add {
    type = "sprite-button",
    sprite = "entity/logistic-robot",
    style = "slot_button",
    name = "logistics-insights-logistics_bots",
    tags = { follow = true }
  }
  player_table.ui.network.requesters = bots_table.add {
    type = "sprite-button",
    sprite = "item/requester-chest",
    style = "slot_button",
    name = "logistics-insights-requesters",
    tags = { follow = false }
  }
  player_table.ui.network.providers = bots_table.add {
    type = "sprite-button",
    sprite = "item/passive-provider-chest",
    style = "slot_button",
    name = "logistics-insights-providers",
    tags = { follow = false }
  }
  player_table.ui.network.storages = bots_table.add {
    type = "sprite-button",
    sprite = "item/storage-chest",
    style = "slot_button",
    name = "logistics-insights-storages",
    tags = { follow = false }
  }
end -- add_network_row

local function update_startstop_button(player_table)
  -- Update button appearance to reflect current state
  if not player_data then
    return
  end
  local element = player_table.ui["startstop"]

  if element then
    if player_data.is_paused(player_table) then
      element.sprite = "li_play"
    else
      element.sprite = "li_pause"
    end
  end
end

local function add_sorted_item_row(player_table, gui_table, title, button_title, need_progressbar)
  player_data.register_ui(player_table, title)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal"
  }
  hcell.style.horizontally_stretchable = true

  -- Add left-aligned label
  hcell.add {
    type = "label",
    caption = {"item-row." .. title .. "-title"},
    style = "heading_2_label",
    tooltip = {"", {"item-row." .. title .. "-tooltip"}}
  }

  if button_title then
    -- Add flexible spacer that pushes button to the right
    local space = hcell.add {
      type = "empty-widget",
      style = "draggable_space",
      name = "spacer" .. title,
    }
    space.style.horizontally_stretchable = true

    -- Determine the sprite based on button type and current state
    local sprite, tip
    if button_title == "startstop" then
      sprite = "li_pause"
      tip = {"item-row.toggle-gathering-tooltip"}
    elseif button_title == "clear" then
      sprite = "utility/trash"
      tip = {"item-row.clear-history-tooltip"}
    end

    -- Add right-aligned button that's vertically centered with the label
    local row_button = hcell.add {
      type = "sprite-button",
      style = "mini_button", -- Small button size
      sprite = sprite,
      name = "logistics-insights-sorted-" .. button_title,
      tooltip = tip
    }

    -- Make button vertically centered with a small top margin for alignment
    row_button.style.top_margin = 2
    hcell.style.vertical_align = "center"
    if button_title == "startstop" then
      player_table.ui.startstop = row_button
    end
  end

  if need_progressbar then
    local progressbar = cell.add {
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
end -- add_sorted_item_row

-- Chreate the main table with all the rows needed
local function create_bots_table(player, player_table)
  if not player or not player_table then
    return
  end

  local window = player.gui.screen.logistics_insights_window
  if not window then
    return -- can't find the window
  end

  local bots_table = player_table.bots_table
  if not bots_table or not bots_table.valid then
    return -- can't find the bots table, something is wrong
  end

  bots_table.clear()

  if player_table.settings.show_delivering then
    add_sorted_item_row(player_table, bots_table, "deliveries-row", "startstop", true)
  end

  if player_table.settings.show_history and storage.delivery_history then
    add_sorted_item_row(player_table, bots_table, "totals-row", "clear", false)
    add_sorted_item_row(player_table, bots_table, "avgticks-row", nil, false)
  end

  if player_table.settings.show_activity then -- There is an option for this as it's expensive
    add_bot_activity_row(bots_table, player_table)
  end
  add_network_row(bots_table, player_table)
end

-- Caching frequently accessed values
local cached_chunk_size = 0
local cached_tooltip_complete = nil
local cached_tooltip_data = {}

-- Function to update cached values when settings change
function bots_gui.update_chunk_size_cache()
  local new_chunk_size = player_data.get_singleplayer_table().settings.chunk_size or 400
  
  -- Only invalidate caches if the value actually changed
  if new_chunk_size ~= cached_chunk_size then
    cached_chunk_size = new_chunk_size
    cached_tooltip_complete = nil
    cached_tooltip_data = {}
  end
end

local function update_progressbar(progressbar, progress)
  if not progressbar or not progressbar.valid then
    return
  end
  
  -- Initialize the cache if it's not set yet
  if cached_chunk_size == 0 then
    bots_gui.update_chunk_size_cache()
  end
  
  if not progress or progress.total == 0 then
    -- Create tooltip only once for the "complete" state
    if not cached_tooltip_complete then
      cached_tooltip_complete = {"bots-gui.chunk-size-tooltip", cached_chunk_size}
    end
    
    -- Only update if needed (value might already be 1)
    if progressbar.value ~= 1 then
      progressbar.value = 1
    end
    
    progressbar.tooltip = cached_tooltip_complete
  else
    -- Calculate the new value
    local new_value = progress.current / progress.total

    if math.abs(progressbar.value - new_value) > 0.01 then
      progressbar.value = new_value
      
      local current_minus_one = progress.current - 1
      local percentage = math_floor((current_minus_one / progress.total) * 100 + 0.5)
      
      local cache_key = current_minus_one .. "_" .. progress.total
      if not cached_tooltip_data[cache_key] then
        if table_size(cached_tooltip_data) > 500 then
          cached_tooltip_data = {}
        end
        cached_tooltip_data[cache_key] = {"bots-gui.chunk-processed-tooltip-1chunksize-2processed-3total-4percent", cached_chunk_size, current_minus_one, progress.total, percentage}
      end
      
      progressbar.tooltip = cached_tooltip_data[cache_key]
    end
  end
end


-------------------------------------------------------------------------------
-- Create main window and all rows needed based on settings
-------------------------------------------------------------------------------
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
local function update_sorted_item_row(player_table, title, all_entries, sort_fn, number_field, clearing)

  local function getcelltooltip(entry)
    local tip
    local quality = entry.localised_quality_name or entry.quality_name
    local name = entry.localised_name or entry.item_name
    if number_field == "count" then
      tip = {"", {"item-row.count-field-tooltip-1count-2quality-3itemname", entry.count, quality, name}}
    elseif number_field == "ticks" then
      tip = {"", {"item-row.ticks-field-tooltip-1ticks-2count-3quality-4itemname", entry.ticks, entry.count, quality, name}}
    elseif number_field == "avg" then
      local int_part = math_floor(entry.avg)
      local decimal_part = math_floor((entry.avg - int_part) * 10 + 0.5)
      local ticks_formatted = int_part .. "." .. decimal_part
      tip = {"", {"item-row.avg-field-tooltip-1ticks-2count-3quality-4itemname", ticks_formatted, entry.count, quality, name}}
    end
    return tip
  end

  -- If paused, just disable all the fields, unless we just cleared history
  if player_data.is_paused(player_table) and not clearing then
    for i = 1, player_table.settings.max_items do
      local cell = player_table.ui[title].cells[i]
      cell.enabled = false
    end
    return
  end

  -- Pre-allocate array by counting entries first
  local entry_count = 0
  for _ in pairs(all_entries) do
    entry_count = entry_count + 1
  end

  -- Only create as large an array as needed for display
  local max_needed = math_min(entry_count, player_table.settings.max_items)
  local sorted_entries = {}
  
  if entry_count <= max_needed then
    local idx = 1
    for _, entry in pairs(all_entries) do
      sorted_entries[idx] = entry
      idx = idx + 1
    end
    table_sort(sorted_entries, sort_fn)
  else
    -- For large collections, maintain a sorted top-N list
    local idx = 1
    for _, entry in pairs(all_entries) do
      if idx <= max_needed then
        sorted_entries[idx] = entry
        idx = idx + 1
      else
        -- Once we have max_needed items, sort them
        if idx == max_needed + 1 then
          table_sort(sorted_entries, sort_fn)
          idx = idx + 1 -- Increment to avoid re-sorting
        end
        
        -- Check if this entry belongs in our top-N
        if sort_fn(entry, sorted_entries[max_needed]) then
          -- Find insertion point (binary search would be more efficient for large max_needed)
          local insert_pos = max_needed
          while insert_pos > 1 and sort_fn(entry, sorted_entries[insert_pos-1]) do
            insert_pos = insert_pos - 1
          end
          
          -- Shift elements to make room
          for j = max_needed, insert_pos + 1, -1 do
            sorted_entries[j] = sorted_entries[j-1]
          end
          
          -- Insert the new element
          sorted_entries[insert_pos] = entry
        end
      end
    end
  end

  -- Add up to max_items entries
  local count = 0
  for _, entry in ipairs(sorted_entries) do
    if count >= player_table.settings.max_items then break end
    if not player_table.ui[title] then break end
    local cell = player_table.ui[title].cells[count + 1]
    cell.sprite = "item/" .. entry.item_name
    cell.quality = entry.quality_name or "normal"
    cell.number = entry[number_field]
    cell.tooltip = getcelltooltip(entry)
    cell.enabled = not player_data.is_paused(player_table)
    count = count + 1
  end

  -- Pad with blank elements
  while count < player_table.settings.max_items do
    if not player_table.ui[title] then break end
    local cell = player_table.ui[title].cells[count + 1]
    cell.sprite = ""
    cell.tooltip = ""
    cell.number = nil
    cell.enabled = false
    count = count + 1
  end
end -- update_sorted_item_row

local function update_bot_activity_row(player_table)
  local reset_activity_buttons = function(ui_table, sprite, number, tip, disable)
    -- Reset all cells in the ui_table to empty
    for _, cell in pairs(ui_table) do
      if cell and cell.cell and cell.cell.valid and cell.cell.type == "sprite-button" then
        cell = cell.cell -- Get the actual sprite-button
        if sprite then cell.sprite = "" end
        if tip then cell.tooltip = "" end
        if number then cell.number = nil end
        if disable then cell.enabled = false end
      end
    end
  end

  local function get_robotstr(window, num)
    if window.include_construction then
      return {"bots-gui.format-all-robots", num}
    else
      return {"bots-gui.format-logistics-robots", num}
    end
  end

  if player_table.network then
    for key, window in pairs(player_table.ui.activity.cells) do
      if window.cell.valid then
        local no_data = false
        -- Even if paused, the Total and Available robot counts are available
        local is_active = not player_data.is_paused(player_table) or
                          key == "logistic-robot-total" or key == "logistic-robot-available"
         -- If real time delivery is disabled, the Pickup/Delivery buttons should be inactive too
        if is_active and (key == "picking" or key == "delivering") and not show_deliveries(player_table) then
          is_active = false -- Whether the cell is enabled or greyed out
          no_data = true -- whether the tooltip needs to be empty and no number displayed
        end
        local num = storage.bot_items[key] or 0
        window.cell.number = num
        window.cell.enabled = true
        local robotstr = get_robotstr(window, num)
        local qualities_tooltip = {""}

        local qualities_table = window.qualitytable
        local extra_newline = ""
        if qualities_table then
          --  Augment the tooltip with a list of qualities found, if enabled in settings
          qualities_tooltip = tooltips_helper.get_quality_tooltip_line(nil, player_table, storage[qualities_table])
        end

        if window.clicktip and is_active then
          -- Only show the "what happens if you click" tooltip if the button is active
          if qualities_table then
            extra_newline = "\n"
          end
          if window.onwithpause or not player_table.settings.pause_for_bots then
            window.cell.tooltip = {"", robotstr, window.tip, "\n", qualities_tooltip, extra_newline, {"bots-gui.show-location-tooltip"}}
          else
            window.cell.tooltip = {"", robotstr, window.tip, "\n", qualities_tooltip, extra_newline, {"bots-gui.show-location-and-pause-tooltip"}}
          end
        else
          if no_data then
            window.cell.tooltip = ""
            window.cell.number = nil
          else
            window.cell.tooltip = {"", robotstr, window.tip, "\n", qualities_tooltip}
          end
        end
        window.cell.enabled = is_active
      end
    end
  else -- No network, reset all activity buttons
    reset_activity_buttons(player_table.ui.activity.cells, false, true, true, false)
  end
end -- update_bot_activity_row

local function update_network_row(player_table)
  local function update_element(cell, value, localized_tooltip, clicktip)
    if cell and cell.valid then
      cell.number = value
      if localized_tooltip then
        if clicktip then
          cell.tooltip = {"", {localized_tooltip, value},  "\n", {clicktip}}
        else
          cell.tooltip = {localized_tooltip, value}
        end
      else
        cell.tooltip = ""
      end
    end
  end

  local function update_key_element(cell, value, main_completed_tooltip)
    if cell and cell.valid then
      cell.number = value
      cell.tooltip = {"", main_completed_tooltip}
    end
  end

  local function update_complex_element(cell, value, localized_tooltip, clicktip)
    if cell and cell.valid then
      cell.number = value
      if localized_tooltip then
        if clicktip then
          cell.tooltip = {"", localized_tooltip, "\n", {clicktip}}
        else
          cell.tooltip = {"", localized_tooltip, "\n"}
        end
      else
        cell.tooltip = ""
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

  local function create_networkid_information_tooltip(network, network_id, is_fixed, clicktip)
    -- Line 1: Network ID: xyz (Dynamic/Fixed)
    local tip = {}
    tip = tooltips_helper.add_networkid_tip(tip, network_id, is_fixed)

    --- Located on: (Planet)
    tip = tooltips_helper.add_network_surface_tip(tip, network)

    -- History data: "Disabled in settings", "Paused", or "Collected for <time>"
    tip = tooltips_helper.add_network_history_tip(tip, player_table)

    return {"", tip, "\n\n", {clicktip}}
  end

  local function create_logistic_bots_tooltip(network)
    -- Line 1: Show no of bots
    local tip = { "", {"network-row.logistic-bots-tooltip", network.all_logistic_robots}, "\n" }

    -- Line 2: Show quality counts
    tip = tooltips_helper.get_quality_tooltip_line(tip, player_table, storage.total_bot_qualities, false)
    return tip
  end

  local networkidclicktip
  if player_table.fixed_network then
    networkidclicktip = "network-row.follow-network-tooltip"
  else
    networkidclicktip = "network-row.fixed-network-tooltip"
  end

  if player_table.network and player_table.network.valid then
    -- Network ID cell and tooltip
    local network_id = player_table.network.network_id
    local networkidtip = create_networkid_information_tooltip(player_table.network, network_id, player_table.fixed_network, networkidclicktip)
    update_key_element(player_table.ui.network.id, network_id, networkidtip)

    -- Roboports cell and tooltip
    update_complex_element(player_table.ui.network.roboports, table_size(player_table.network.cells),
      tooltips_helper.create_count_with_qualities_tip(player_table, "network-row.roboports-tooltip", table_size(player_table.network.cells), storage.roboport_qualities),
      "bots-gui.show-location-tooltip")

    --  All Logistic Bots cell and tooltip
    local bottip
    if player_table.settings.pause_for_bots then
      bottip = "bots-gui.show-location-and-pause-tooltip"
    else
      bottip = "bots-gui.show-location-tooltip"
    end
    update_complex_element(player_table.ui.network.logistics_bots, player_table.network.all_logistic_robots, create_logistic_bots_tooltip(player_table.network), bottip)

    -- Requesters, Providers and Storages cells and tooltips
    update_element(player_table.ui.network.requesters, table_size(player_table.network.requesters), "network-row.requesters-tooltip", "bots-gui.show-location-tooltip")
    update_element(player_table.ui.network.providers, table_size(player_table.network.providers) - table_size(player_table.network.cells), "network-row.providers-tooltip", "bots-gui.show-location-tooltip")
    update_element(player_table.ui.network.storages, table_size(player_table.network.storages), "network-row.storages-tooltip", "bots-gui.show-location-tooltip")
  else
    reset_network_buttons(player_table.ui.network, false, true, true, false)
    if not player_table.fixed_network then
      networkidclicktip = "network-row.no-network-clicktip"
    end
    update_element(player_table.ui.network.id, nil, "network-row.no-network-tooltip", networkidclicktip)
  end
end -- update_network_row

-------------------------------------------------------------------------------
-- Main function to update the bots GUI, assumes all the elements exist
-------------------------------------------------------------------------------

function bots_gui.update(player, player_table, clearing)
  -- Update the bots table with current data, do not recreate it
  if not player or not player.valid or not player_table then
    return -- no player table, can't do anything
  end
  -- Update shortcut toggle state to match window visibility
  player.set_shortcut_toggled("logistics-insights-toggle", player_table.bots_window_visible)

  if not player_table.ui or not player_table.bots_window_visible then
    return
  end

  bots_gui.ensure_ui_consistency(player, player_table)

  if player_table.settings.show_delivering then
    update_sorted_item_row(
      player_table,
      "deliveries-row",
      storage.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count",
      clearing
    )
  end
  if player_table.settings.show_history and storage.delivery_history then
    update_sorted_item_row(
      player_table,
      "totals-row",
      storage.delivery_history,
      function(a, b) return a.count > b.count end,
      "count",
      clearing
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
      "avgticks-row",
      storage.delivery_history,
      function(a, b) return a.avg > b.avg end,
      "avg",
      clearing
    )
  end
  update_bot_activity_row(player_table)
  update_network_row(player_table)
end -- update contents

function bots_gui.update_cells_chunk_progress(player_table, progress)
  if player_table.ui == nil then return end
  if player_table.bots_window_visible then
    update_progressbar(player_table.ui.activity.progressbar, progress)
  end
end

function bots_gui.update_bot_chunk_progress(player_table, progress)
  if player_table.ui == nil then return end
  if player_table.bots_window_visible then
    update_progressbar(player_table.ui["deliveries-row"].progressbar, progress)
  end
end

-------------------------------------------------------------------------------
-- Functions to find items to highlight on the map when clicked
-------------------------------------------------------------------------------

---@param cell_list LuaLogisticCell[]
---@return LuaEntity[]|nil  -- Returns a list of bots
local function find_charging_robots(player_table, cell_list)
  if not cell_list or #cell_list == 0 then
    return nil
  end
  local bot_list = {}
  for _, cell in pairs(cell_list) do
    if cell and cell.valid and cell.charging_robots then
      for _, bot in pairs(cell.charging_robots) do
        -- if player_data.is_included_robot(bot) then
        table.insert(bot_list, bot)
        -- end
      end
    end
  end
  return bot_list
end

---@param cell_list LuaLogisticCell[]
---@return LuaEntity[]|nil  -- Returns a list of bots
local function find_waiting_to_charge_robots(player_table, cell_list)
  if not cell_list or #cell_list == 0 then
    return nil
  end
  local bot_list = {}
  for _, cell in pairs(cell_list) do
    if cell and cell.valid and cell.to_charge_robots then
      for _, bot in pairs(cell.to_charge_robots) do
        -- if player_data.is_included_robot(bot) then
        table.insert(bot_list, bot)
        -- end
      end
    end
  end
  return bot_list
end

local function get_item_list_and_focus(item_list)
  local rando = utils.get_random(item_list)
  return {items = item_list, item = rando, follow = false}
end

local function get_item_list_and_focus_mobile(item_list)
  local rando = utils.get_random(item_list)
  if rando then
    return {items = item_list, item = rando, follow = true}
  else
    return {items = item_list, item = nil, follow = false}
  end
end

local function get_item_list_and_focus_from_player_table(player_table, find_fn)
  if find_fn == nil or player_table == nil or player_table.network == nil or player_table.network.cells == nil then
    return {items = nil, item = nil, follow = false}
  end
  local filtered_list = find_fn(player_table, player_table.network.cells)
  if filtered_list == nil or #filtered_list == 0 then
    return {items = nil, item = nil, follow = false}
  else
    return get_item_list_and_focus_mobile(filtered_list)
  end
end

local function get_item_list_and_focus_owner(item_list)
  local ownerlist = {}
  for _, item in pairs(item_list) do
    if item and item.valid and item.owner then
      table.insert(ownerlist, item.owner)
    end
  end
  return get_item_list_and_focus(ownerlist)
end

local function get_item_list_and_focus_from_botlist(bot_list, order_type)
  if not bot_list or #bot_list == 0 then
    return {items = nil, item = nil, follow = false}
  end
  local filtered_list = {}
  for _, bot in pairs(bot_list) do
    if bot and bot.valid  and table_size(bot.robot_order_queue) > 0 then
     if bot.robot_order_queue[1].type == order_type then
      table.insert(filtered_list, bot)
     end
    end
  end
  return get_item_list_and_focus_mobile(filtered_list)
end

local function get_item_list_and_focus_exclude_roboports(item_list)
  local list = {}
  for _, item in pairs(item_list) do
    if item and item.valid and item.type ~= "roboport" then
      table.insert(list, item)
    end
  end
  return get_item_list_and_focus(list)
end

local get_list_function = {
  -- Activity row buttons
  ["logistics-insights-logistic-robot-total"] = function(pd)
    return get_item_list_and_focus_mobile(pd.network.logistic_robots)
  end,
  ["logistics-insights-charging-robot"] = function(pd)
    return get_item_list_and_focus_from_player_table(pd, find_charging_robots)
  end,
  ["logistics-insights-waiting-for-charge-robot"] = function(pd)
    return get_item_list_and_focus_from_player_table(pd, find_waiting_to_charge_robots)
  end,
  ["logistics-insights-delivering"] = function(pd)
    return get_item_list_and_focus_from_botlist(pd.network.logistic_robots, defines_robot_order_type_deliver)
  end,
  ["logistics-insights-picking"] = function(pd)
    return get_item_list_and_focus_from_botlist(pd.network.logistic_robots, defines_robot_order_type_pickup)
  end,
  -- Network row buttons
  ["logistics-insights-roboports"] = function(pd)
    return get_item_list_and_focus_owner(pd.network.cells)
  end,
  ["logistics-insights-requesters"] = function(pd)
    return get_item_list_and_focus(pd.network.requesters)
  end,
  ["logistics-insights-logistics_bots"] = function(pd)
    return get_item_list_and_focus_mobile(pd.network.logistic_robots)
  end,
  ["logistics-insights-providers"] = function(pd)
    return get_item_list_and_focus_exclude_roboports(pd.network.providers)
  end,
  ["logistics-insights-storages"] = function(pd)
    return get_item_list_and_focus(pd.network.storages)
  end,
}

---@param player LuaPlayer
---@param player_table PlayerData|nil
---@param element LuaGuiElement sprite-button
---@param focus_on_element boolean
function bots_gui.highlight_locations_on_map(player, player_table, element, focus_on_element)
  local fn = get_list_function[element.name]
  if not fn then
    return
  end

  if player_table == nil or player_table.network == nil then
    return -- Fix crash when outside of network
  end

  local viewdata = fn(player_table)
  if viewdata == nil or viewdata.item == nil then
    return
  end

  if viewdata.follow and player.mod_settings["li-pause-for-bots"].value then
    game_state.freeze_game()
  end
  local toview = {
    position = viewdata.item.position,
    surface = viewdata.item.surface.name,
    zoom = 0.8,
    items = viewdata.items,
  }
  ResultLocation.open(player, toview, focus_on_element)
end

-- ONCLICK
function bots_gui.onclick(event)
  if utils.starts_with(event.element.name, "logistics-insights") then
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()
    if event.element.name == "logistics-insights-unfreeze" then
      -- Unfreeze the game after it's been frozen
      ResultLocation.clear_markers(player)
      game_state.unfreeze_game()
    elseif event.element.name == "logistics-insights-freeze" then
      -- Freeze the game so player can inspect the state
      game_state.freeze_game()
    elseif event.element.name == "logistics-insights-step" then
      -- Single-step the game to see what happens
      game_state.step_game()
    elseif event.element.name == "logistics-insights-network-id" then
      -- Clicking the network ID button toggles between fixed and dynamic network
      event.element.toggled = not event.element.toggled
      player_table.fixed_network = event.element.toggled
    elseif event.element.name == "logistics-insights-sorted-clear" then
      -- Clear the delivery history and clear the timer
      storage.delivery_history = {}
      if player_table and player_table.history_timer then
        player_table.history_timer:reset()
      end
      bots_gui.update(player, player_table, true)
    elseif event.element.name == "logistics-insights-sorted-startstop" then
      -- Start/stop collecting delivery history
      player_data.toggle_history_collection(player_table)
      update_startstop_button(player_table)
      bots_gui.update(player, player_table, false)
    elseif event.element.tags and player then
      -- Highlight elements. If right-click, also focus on random element
      bots_gui.highlight_locations_on_map(player, player_table, event.element, event.button == defines.mouse_button_type.right)
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
    if player_table then
      player_table.window_location = event.element.location
    end
  end
end)

return bots_gui
