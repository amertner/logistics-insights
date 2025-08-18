-- Networks window: skeleton UI only (no internals yet)

local networks_window = {}

local flib_format = require("__flib__.format")

local WINDOW_NAME = "li_networks_window"

--- Create the Networks window for a player
--- @param player LuaPlayer
function networks_window.create(player)
  if not player or not player.valid then return end

  -- Destroy existing instance first
  if player.gui.screen[WINDOW_NAME] then
    player.gui.screen[WINDOW_NAME].destroy()
  end

  -- Root frame
  local window = player.gui.screen.add {
    type = "frame",
    name = WINDOW_NAME,
    direction = "vertical",
    style = "botsgui_frame_style",
    visible = true,
  }
  -- Make the window taller by default while keeping it flexible
  window.style.minimal_height = 520

  -- Title bar with dragger, pin, and close
  local titlebar = window.add {
    type = "flow",
    name = WINDOW_NAME .. "-titlebar",
    direction = "horizontal",
  }
  titlebar.drag_target = window

  titlebar.add {
    type = "label",
    caption = "Networks",
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local dragger = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    height = 24,
    right_margin = 4,
    ignored_by_interaction = true,
  }
  dragger.style.horizontally_stretchable = true
  dragger.style.vertically_stretchable = true

  -- Content: scrollable table to align uneven-width data
  local scroll = window.add {
    type = "scroll-pane",
    name = WINDOW_NAME .. "-scroll",
    vertical_scroll_policy = "auto",
    horizontal_scroll_policy = "never",
  }
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.style.padding = 8
  -- Ensure a comfortably tall content area by default
  scroll.style.minimal_height = 480

  local table_el = scroll.add {
    type = "table",
    name = WINDOW_NAME .. "-table",
    column_count = 7,
    draw_horizontal_lines = true,
  }
  table_el.style.horizontal_spacing = 12
  table_el.style.vertical_spacing = 4
  table_el.style.column_alignments[1] = "right"
  table_el.style.column_alignments[2] = "center"
  table_el.style.column_alignments[3] = "right"
  table_el.style.column_alignments[5] = "right"
  table_el.style.column_alignments[6] = "center"
  table_el.style.column_alignments[7] = "center"

  -- Header row: mix of text and icons
  local function add_header_label(caption)
    table_el.add{ type = "label", caption = caption, style = "bold_label" }
  end
  local function add_header_icon(sprite, tooltip)
    local e = table_el.add{ type = "sprite", sprite = sprite, tooltip = tooltip }
    -- Make header icons bigger
    e.style.width = 28
    e.style.height = 28
    e.style.stretch_image_to_widget_size = true
    return e
  end
  -- ID (text)
  add_header_label("ID")
  -- Surface (Nauvis icon)
  add_header_icon("space-location/nauvis", {"", "Surface"})
  -- Bots (icon)
  add_header_icon("entity/logistic-robot", {"", "Total bots"})
  -- Insights (text)
  add_header_label("Insights")
  -- Updated (hourglass icon)
  add_header_icon("virtual-signal/signal-hourglass", {"", "Last updated/sec"})
  -- Settings (same icon as row data)
  add_header_icon("utility/rename_icon", {"", "Settings"})
  -- Clear/stop
  add_header_icon("utility/trash", {"", "Stop monitoring"})

  -- Optional: initial size; content is stretchable to support future resize logic
  window.force_auto_center()
end

--- Destroy the Networks window for a player
--- @param player LuaPlayer
function networks_window.destroy(player)
  if not player or not player.valid then return end
  local w = player.gui.screen[WINDOW_NAME]
  if w then w.destroy() end
end

--- Toggle visibility of the Networks window
--- @param player LuaPlayer
function networks_window.toggle_window_visible(player)
  if not player or not player.valid then return end
  local w = player.gui.screen[WINDOW_NAME]
  if not w then
    networks_window.create(player)
    return
  end
  w.visible = not w.visible
end

--- Ensure the Networks table has exactly `count` data rows (below the header).
--- Rows are created with placeholder cells so they can be filled later without resizing.
--- @param player LuaPlayer
--- @param count integer Expected range 0-100
function networks_window.set_network_count(player, count)
  if not player or not player.valid then return end
  if type(count) ~= "number" then return end
  if count < 0 then count = 0 end

  local window = player.gui.screen[WINDOW_NAME]
  if not window or not window.valid then return end
  local scroll = window[WINDOW_NAME .. "-scroll"]
  if not scroll or not scroll.valid then return end
  local table_el = scroll[WINDOW_NAME .. "-table"]
  if not table_el or not table_el.valid then return end

  local columns = table_el.column_count or 6
  local header_cells = columns -- One header row already present

  local child_count = #table_el.children
  local current_rows = 0
  if child_count >= header_cells then
    current_rows = math.floor((child_count - header_cells) / columns)
  end

  local function add_cell(row_index, col_key)
    local name = string.format("%s-cell-%d-%s", WINDOW_NAME, row_index, col_key)
    if col_key == "id" then
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = false
      el.style.horizontal_align = "right"
      return el
    elseif col_key == "surface" then
      -- Sprite placeholder; will be set later
      return table_el.add{ type = "sprite", name = name, sprite = "utility/questionmark" }
    elseif col_key == "bots" then
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
      return el
    elseif col_key == "insights" then
      local flow = table_el.add{ type = "flow", name = name, direction = "horizontal" }
      for i = 1, 4 do
        flow.add{ type = "sprite-button", style = "slot_button", name = string.format("%s-btn-%d", name, i), sprite = "li_arrow", visible = false }
      end
      return flow
    elseif col_key == "updated" then
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = false
      el.style.horizontal_align = "right"
      return el
    elseif col_key == "settings" then
      -- Use a mini button for settings
      local btn = table_el.add{ type = "sprite-button", name = name, style = "mini_button", sprite = "utility/rename_icon" }
      btn.style.top_margin = 2
      return btn
    elseif col_key == "trash" then
      -- Use a mini button for settings
      local btn = table_el.add{ type = "sprite-button", name = name, style = "mini_button", sprite = "utility/trash" }
      btn.style.top_margin = 2
      return btn
    else
      return table_el.add{ type = "label", name = name, caption = "" }
    end
  end

--- Update all data rows in the networks window from storage.networks
--- @param player LuaPlayer
function networks_window.update(player)
  if not player or not player.valid then return end
  local window = player.gui.screen[WINDOW_NAME]
  if not window or not window.valid then return end
  local scroll = window[WINDOW_NAME .. "-scroll"]
  if not scroll or not scroll.valid then return end
  local table_el = scroll[WINDOW_NAME .. "-table"]
  if not table_el or not table_el.valid then return end

  local list = {}
  if storage and storage.networks then
    for _, nw in pairs(storage.networks) do
      list[#list+1] = nw
    end
  end
  table.sort(list, function(a,b) return (a.id or 0) < (b.id or 0) end)

  -- Ensure row count matches
  networks_window.set_network_count(player, #list)

  local function el(name)
    return table_el[name]
  end

  for i, nw in ipairs(list) do
    -- ID
    local idcell = el(string.format("%s-cell-%d-id", WINDOW_NAME, i))
    if idcell and idcell.valid then idcell.caption = tostring(nw.id or "") end

    -- Surface (sprite + tooltip localised name)
    local surf = nw.surface or ""
    local scell = el(string.format("%s-cell-%d-surface", WINDOW_NAME, i))
    if scell and scell.valid then
      if scell.type == "sprite" then
        local surface = nw.surface
        if surface == "" then
          surface = "space-location-unknown"
        end
        scell.sprite = "space-location/" .. surface
      end
    end

    -- Bots (sprite-button with number overlay)
    local botscell = el(string.format("%s-cell-%d-bots", WINDOW_NAME, i))
    if botscell and botscell.valid and nw then
      local bots = nw.bot_items["logistic-robot-total"]
      botscell.caption = tostring(bots)
    end

    -- Insights (no data yet; keep sub-buttons hidden/cleared)
    local insflow = el(string.format("%s-cell-%d-insights", WINDOW_NAME, i))
    if insflow and insflow.valid and insflow.children then
      for _, child in ipairs(insflow.children) do
        child.visible = false
      end
    end

    -- Updated (seconds since last_active_tick)
    local updatedcell = el(string.format("%s-cell-%d-updated", WINDOW_NAME, i))
    if updatedcell and updatedcell.valid then
      local lt = nw.last_active_tick or nw.last_accessed_tick or 0
      local age_ticks = (game and game.tick or 0) - lt
      if age_ticks < 0 then age_ticks = 0 end
      time_str = flib_format.time(age_ticks, false)
      updatedcell.caption = time_str
      updatedcell.tooltip = nil
    end

    -- Settings (no-op placeholder)
    local setcell = el(string.format("%s-cell-%d-settings", WINDOW_NAME, i))
    if setcell and setcell.valid and setcell.type == "sprite-button" then
      setcell.sprite = setcell.sprite ~= "" and setcell.sprite or "utility/rename_icon"
    end

    local setcell = el(string.format("%s-cell-%d-trash", WINDOW_NAME, i))
    if setcell and setcell.valid and setcell.type == "sprite-button" then
      setcell.sprite = setcell.sprite ~= "" and setcell.sprite or "utility/trash"
    end
  end
end

  if current_rows < count then
    for r = current_rows + 1, count do
      add_cell(r, "id")
      add_cell(r, "surface")
      add_cell(r, "bots")
      add_cell(r, "insights")
      add_cell(r, "updated")
      add_cell(r, "settings")
      add_cell(r, "trash")
    end
  elseif current_rows > count then
    local to_remove = (current_rows - count) * columns
    for _ = 1, to_remove do
      local children = table_el.children
      local last = children[#children]
      if last and last.valid then last.destroy() end
    end
  end
end

return networks_window
