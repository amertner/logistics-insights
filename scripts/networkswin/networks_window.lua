-- Networks window: Show a summary of all networks seen
local networks_window = {}

local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local find_and_highlight = require("scripts.mainwin.find_and_highlight")

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
      return el
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      local count = table_size(nw.players_set or {})
      el.caption = tostring(count)
      -- Build a tooltip with a list of players in the network
      local list = {}
      if nw.players_set then
        for idx, present in pairs(nw.players_set) do
          if present then
            local player = game.get_player(idx)
            if player and player.valid then
              list[#list+1] = player.name
            end
          end
        end
      end
      table.sort(list)
      el.tooltip = table.concat(list, ", ")
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
    key = "idlebots",
    header = { type = "sprite", sprite = "virtual-signal/signal-battery-full", tooltip = {"networks-window.idlebots-tooltip"} },
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
      if nw.bot_items and nw.bot_items[ "logistic-robot-available"] then
        bots = nw.bot_items[ "logistic-robot-available"] or 0
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
      if nw and table_size(nw.players_set) == 0 and nw.bg_paused then
        el.caption = "||"
        el.tooltip = {"networks-window.paused-tooltip"}
        return
      end
      if nw.id == storage.bg_refreshing_network_id then
        el.caption = "*"
        el.tooltip = {"networks-window.updating-tooltip"}
      else
        local last_tick = nw.last_active_tick or 0
        local age_ticks = (game and game.tick or 0) - last_tick
        if age_ticks < 0 then age_ticks = 0 end
        local time_str = flib_format.time(age_ticks, false)
        el.caption = time_str
        el.tooltip = nil
      end
    end
  },
  {
    key = "actions",
    header = { type = "sprite", sprite = "item/iron-gear-wheel", tooltip = {"networks-window.actions-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local flow = table_el.add {
        type = "flow",
        name = name,
        direction = "horizontal",
      }
      local btn = flow.add{ type = "sprite-button", name = name .. "-view", style = "mini_button", sprite = "virtual-signal/signal-map-marker", tooltip = {"networks-window.view-tooltip"} }
      btn.style.top_margin = 2
      btn = flow.add{ type = "sprite-button", name = name .. "-pause", style = "mini_button", sprite = "li_pause", tooltip = {"networks-window.pause-tooltip"} }
      btn.style.top_margin = 2
      btn = flow.add{ type = "sprite-button", name = name .. "-settings", style = "mini_button", sprite = "utility/rename_icon", tooltip = {"networks-window.settings-tooltip"} }
      btn.style.top_margin = 2
      btn = flow.add{ type = "sprite-button", name = name .. "-trash", style = "mini_button", sprite = "utility/trash", tooltip = {"networks-window.trash-tooltip"} }
      btn.style.top_margin = 2
      return flow
    end,
    populate = function(el, nw)
      if not (el and el.valid) then return end
      -- Tag the buttons so click handler can find the network
      for _, btn in ipairs(el.children) do
        if btn and btn.valid and btn.type == "sprite-button" then
          local has_players = nw.players_set and table_size(nw.players_set) > 0
          if btn.name:find("trash", 1, true) then
            btn.enabled = not has_players -- Disable if players are using it
          else
            btn.enabled = true -- Enable other buttons regardless
            -- Show the right icon and tooltip for pause button
            if btn.name:find("pause", 1, true) then
              if nw.bg_paused then
                btn.sprite = "li_play"
                btn.tooltip = {"networks-window.unpause-tooltip"}
              else
                btn.sprite = "li_pause"
                btn.tooltip = {"networks-window.pause-tooltip"}
              end
            end
          end
          btn.tags = { network_id = nw.id or 0 }
        end
      end
    end
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
  titlebar.style.vertically_stretchable = false

  local label = titlebar.add {
    type = "label",
    caption = {"networks-window.window-title"},
    style = "frame_title",
    ignored_by_interaction = true,
  }
  label.style.top_margin = -6

  local dragger = titlebar.add {
    type = "empty-widget",
    style = "draggable_space_header",
    height = 48,
    right_margin = 0,
    ignored_by_interaction = true,
  }
  dragger.style.horizontally_stretchable = true
  dragger.style.vertically_stretchable = true
  titlebar.add({
      type = "sprite-button",
      style = "frame_action_button",
      sprite = "utility/close",
      name = WINDOW_NAME .. "-close",
      tooltip = {"networks-window.close-window-tooltip"},
  })

  -- Content: scrollable table to align uneven-width data
  local scroll = window.add {
    type = "scroll-pane",
    name = WINDOW_NAME .. "-scroll",
    vertical_scroll_policy = "auto",
    horizontal_scroll_policy = "never",
  }
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.style.padding = 0
  -- Ensure a comfortably tall content area by default. Maybe add buttons to change size later.
  scroll.style.minimal_height = 180

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

  -- Always show the networks by ID
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
      if col.populate then
        col.populate(el, nw)
      end
    end
  end
end

--- Handle clicks on Networks window mini buttons (settings/trash).
--- Returns true if the event was handled.
---@param event EventData.on_gui_click
---@return boolean Returns true if the main window should be opened as a result
function networks_window.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return false end
  local name = element.name or ""
  local player = game.get_player(event.player_index)

  if player and (name == WINDOW_NAME .. "-close") then
     networks_window.toggle_window_visible(player)
    return false
  end

  -- Only handle Action buttons
  if not name:find(WINDOW_NAME .. "-cell-", 1, true) then return false end

  -- Identify column from the control name
  local row_str, col_key = name:match(WINDOW_NAME .. "%-cell%-(%d+)%-actions%-(%w+)$")
  if not col_key or (col_key ~= "settings" and col_key ~= "trash" and col_key ~= "view" and col_key ~= "pause") then
    return false
  end

  -- Resolve the network id: prefer tags; fallback to row index lookup
  if element.tags then
    local network_id = tonumber(element.tags.network_id)
    local networkdata = network_data.get_networkdata_fromid(network_id)
    local network = networkdata and network_data.get_LuaNetwork(networkdata)

    if col_key == "view" and network then
      -- In map view, focus on a random roboport in the network
      if player and player.valid and network and network.valid then
        find_and_highlight.highlight_network_locations_on_map(
          player,
          network,
          "logistics-insights-roboports", --Highlight roboports
          true -- Focus on an element
        )
      end
      -- Open the main window if not already open
      return true
    elseif col_key == "trash" and network_id then
      -- Remove the network from storage
      if network_data.remove_network(network_id) then
        local player = game.get_player(event.player_index)
        if player and player.valid then
          -- Update the window after removal
          networks_window.update(player)
        end
      end
    elseif col_key == "pause" and networkdata then
      -- Pause/unpause background refresh for this network
      if networkdata.bg_paused then
        networkdata.bg_paused = nil
      else
        networkdata.bg_paused = true
      end
      if networkdata.bg_paused and storage.bg_refreshing_network_id == network_id then
        -- If we just paused the network being refreshed, clear the refresh state
        storage.bg_refreshing_network_id = nil
      end
    end
  end
  return false
end

return networks_window
