-- Networks window: Show a summary of all networks seen
local networks_window = {}

local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")

local WINDOW_NAME = "li_networks_window"

-- Column configuration for Networks window
-- key: column id used in element names
-- header: { type = "sprite"|"label", sprite?, caption?, tooltip? }
-- align: "left"|"center"|"right"
-- add_cell: function(table_el, name) -> LuaGuiElement
local cell_setup = {
  {
    key = "id",
    header = { type = "sprite", sprite = "virtual-signal/signal-L", tooltip = {"networks-window.id-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = false
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw)
      if el and el.valid then el.caption = tostring(nw.id or "") end
    end
  },
  {
    key = "surface",
    header = { type = "sprite", sprite = "space-location/nauvis", tooltip = {"networks-window.surface-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      return table_el.add{ type = "sprite", name = name, sprite = "utility/questionmark" }
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local surface = nw.surface
      if not surface or surface == "" then surface = "space-location-unknown" end
      el.sprite = "space-location/" .. surface
      el.tooltip = surface
    end
  },
  {
    key = "players",
    header = { type = "sprite", sprite = "entity/character", tooltip = {"networks-window.players-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      -- #FIXME: Count online players only
      el.caption = tostring(table_size(nw.players or {}))
    end
  },
  {
    key = "bots",
    header = { type = "sprite", sprite = "entity/logistic-robot", tooltip = {"networks-window.totalbots-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.minimal_width = 40
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local bots = 0
      if nw.bot_items and nw.bot_items["logistic-robot-total"] then
        bots = nw.bot_items["logistic-robot-total"] or 0
      end
      el.caption = tostring(bots)
    end
  },
  {
    key = "undersupply",
    header = { type = "sprite", sprite = "virtual-signal/signal-U", tooltip = {"networks-window.undersupply-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local count = 0
      if nw.suggestions and nw.suggestions.get_cached_list then
        local undersupply = nw.suggestions:get_cached_list("undersupply")
        if undersupply then
          count = table_size(undersupply)
        end
      end
      el.caption = tostring(count)
    end
  },
  {
    key = "suggestions",
    header = { type = "sprite", sprite = "virtual-signal/signal-S", tooltip = {"networks-window.suggestions-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local count = 0
      if nw.suggestions then
        count = nw.suggestions:get_current_count() or 0
      end
      el.caption = tostring(count)
    end
  },
  {
    key = "updated",
    header = { type = "sprite", sprite = "virtual-signal/signal-clock", tooltip = {"networks-window.timesinceupdate-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = true
      el.style.minimal_width = 50
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local lt = nw.last_active_tick or nw.last_accessed_tick or 0
      local age_ticks = (game and game.tick or 0) - lt
      if age_ticks < 0 then age_ticks = 0 end
      local time_str = flib_format.time(age_ticks, false)
      el.caption = time_str
      el.tooltip = nil
    end
  },
  {
    key = "settings",
    header = { type = "sprite", sprite = "utility/rename_icon", tooltip = {"networks-window.settings-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local btn = table_el.add{ type = "sprite-button", name = name, style = "mini_button", sprite = "utility/rename_icon" }
      btn.style.top_margin = 2
      return btn
  end,
  populate = function(el, nw) end
  },
  {
    key = "trash",
    header = { type = "sprite", sprite = "utility/trash", tooltip = {"networks-window.stop-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local btn = table_el.add{ type = "sprite-button", name = name, style = "mini_button", sprite = "utility/trash" }
      btn.style.top_margin = 2
      return btn
  end,
  populate = function(el, nw) end
  },
}

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
    style = "li_networks_frame_style",
    visible = true,
  }
  -- Make the window taller by default while keeping it flexible
  window.style.minimal_height = 200
  window.style.horizontally_stretchable = true
  -- Allow the frame to grow tall; cap at 80% of screen height for usability
  local screen_h = player.display_resolution and player.display_resolution.height or 1080
  local scale = player.display_scale or 1
  local usable = math.floor((screen_h / scale) * 0.8)
  window.style.maximal_height = usable

  -- Title bar with dragger, pin, and close
  local titlebar = window.add {
    type = "flow",
    name = WINDOW_NAME .. "-titlebar",
    direction = "horizontal",
  }
  titlebar.drag_target = window

  titlebar.add {
    type = "label",
    caption = {"networks-window.window-title"},
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local dragger = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    height = 24,
    right_margin = 0,
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
  -- Ensure a comfortably tall content area by default, but let it expand
  scroll.style.minimal_height = 200
  scroll.style.maximal_height = usable - 80 -- leave room for titlebar

  local col_count = #cell_setup
  local table_el = scroll.add {
    type = "table",
    name = WINDOW_NAME .. "-table",
    column_count = col_count,
    draw_horizontal_lines = true,
  }
  table_el.style.horizontal_spacing = 6
  table_el.style.vertical_spacing = 4
  -- Set column alignments as configured
  for idx, col in ipairs(cell_setup) do
    if col.align then
      table_el.style.column_alignments[idx] = col.align
    end
  end

  -- Build header row from cell_setup
  for _, col in ipairs(cell_setup) do
    if col.header.type == "sprite" then
      local e = table_el.add{ type = "sprite", sprite = col.header.sprite, tooltip = col.header.tooltip }
      e.style.width = 26
      e.style.height = 26
      e.style.stretch_image_to_widget_size = true
    else
      table_el.add{ type = "label", caption = col.header.caption or "", style = "bold_label" }
    end
  end

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
function networks_window.update_network_count(player, count)
  if not player or not player.valid then return end
  if type(count) ~= "number" then return end
  if count < 0 then count = 0 end

  local window = player.gui.screen[WINDOW_NAME]
  if not window or not window.valid then return end
  local scroll = window[WINDOW_NAME .. "-scroll"]
  if not scroll or not scroll.valid then return end
  local table_el = scroll[WINDOW_NAME .. "-table"]
  if not table_el or not table_el.valid then return end

  local columns = table_el.column_count or #cell_setup
  local header_cells = columns -- One header row already present

  local child_count = #table_el.children
  local current_rows = 0
  if child_count >= header_cells then
    current_rows = math.floor((child_count - header_cells) / columns)
  end

  local function add_cell(row_index, col_key)
    local name = string.format("%s-cell-%d-%s", WINDOW_NAME, row_index, col_key)
    for _, col in ipairs(cell_setup) do
      if col.key == col_key then
        return col.add_cell(table_el, name)
      end
    end
    return table_el.add{ type = "label", name = name, caption = "" }
  end -- add_cell

  if current_rows < count then
    for r = current_rows + 1, count do
      for _, col in ipairs(cell_setup) do
        add_cell(r, col.key)
      end
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
  networks_window.update_network_count(player, #list)

  for i, nw in ipairs(list) do
    for _, col in ipairs(cell_setup) do
      local name = string.format("%s-cell-%d-%s", WINDOW_NAME, i, col.key)
      local el = table_el[name]
      if col.populate then col.populate(el, nw) end
      -- Ensure default sprites if needed for icon columns
      if col.key == "settings" and el and el.valid and el.type == "sprite-button" and el.sprite == "" then
        el.sprite = "utility/rename_icon"
      elseif col.key == "trash" and el and el.valid and el.type == "sprite-button" and el.sprite == "" then
        el.sprite = "utility/trash"
      end
    end
  end
end

return networks_window
