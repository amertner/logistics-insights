-- Networks window: Show a summary of all networks seen
local networks_window = {}

local flib_format = require("__flib__.format")
local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local find_and_highlight = require("scripts.mainwin.find_and_highlight")
local utils = require("scripts.utils")
local network_settings = require("scripts.networkswin.network_settings")

local WINDOW_NAME = "li_networks_window"
local WINDOW_MIN_HEIGHT = 110-3*24 -- Room for 0 networks
local WINDOW_MAX_HEIGHT = 110+10*24 -- Room for 12 networks
local WINDOW_HEIGHT_STEP = 24

-- Column configuration for Networks window
-- key: column id used in element names
-- header: { type = "sprite"|"label", sprite?, caption?, tooltip? }
-- align: "left"|"center"|"right"
-- add_cell: function(table_el, name) -> LuaGuiElement
local cell_setup = {
  {
    key = "id",
    header = { type = "sprite", sprite = "technology/logistic-system", tooltip = {"networks-window.id-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "" }
      el.style.horizontally_stretchable = false
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw, pt)
      local idstr = tostring(nw.id or "")
      if el and el.valid then 
        el.caption = idstr 
        el.tooltip = {"networks-window.id-cell-tooltip", idstr}
      end
    end
  },
  {
    key = "surface",
    header = { type = "sprite", sprite = "space-location/nauvis", tooltip = {"networks-window.surface-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local cell = table_el.add{ type = "sprite", name = name, sprite = "utility/questionmark" }
      cell.style.stretch_image_to_widget_size = true
      return cell
    end,
    populate = function(el, nw, pt)
      if not (el and el.valid) then return end
      local surface = nw.surface
      if not surface or surface == "" then surface = "space-location-unknown" end
      el.sprite = utils.get_valid_sprite_path("space-location/", surface)
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
    populate = function(el, nwd, pt)
      if not (el and el.valid) then return end
      local count = network_data.players_in_network(nwd)
      el.caption = tostring(count)
      -- Build a tooltip with a list of players in the network
      local list = {}
      if nwd.players_set then
        for idx, present in pairs(nwd.players_set) do
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
    populate = function(el, nw, pt)
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
    populate = function(el, nw, pt)
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
    header = { type = "sprite", sprite = "li_undersupply", tooltip = {"networks-window.undersupply-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw, pt)
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
    header = { type = "sprite", sprite = "li_suggestions", tooltip = {"networks-window.suggestions-tooltip"} },
    align = "right",
    add_cell = function(table_el, name)
      local el = table_el.add{ type = "label", name = name, caption = "0" }
      el.style.horizontally_stretchable = true
      el.style.horizontal_align = "right"
      return el
    end,
    populate = function(el, nw, pt)
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
    populate = function(el, nwd, pt)
      if not (el and el.valid) then return end
      if nwd.id == storage.bg_refreshing_network_id then
        el.caption = "*"
        el.tooltip = {"networks-window.updating-tooltip"}
      else
        local last_tick = nwd.last_scanned_tick or 0
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
    header = { type = "label", caption = "", tooltip = {"networks-window.actions-tooltip"} },
    align = "center",
    add_cell = function(table_el, name)
      local flow = table_el.add {
        type = "flow",
        name = name,
        direction = "horizontal",
      }
      local btn = flow.add{ type = "sprite-button", name = name .. "-view", style = "mini_button", sprite = "li-map-marker", tooltip = {"networks-window.view-tooltip"} }
      btn.style.top_margin = 2
      btn = flow.add{ type = "sprite-button", name = name .. "-trash", style = "mini_button", sprite = "utility/trash", tooltip = {"networks-window.trash-tooltip"} }
      btn.style.top_margin = 2
      btn = flow.add{ type = "sprite-button", name = name .. "-settings", style = "mini_button", sprite = "li-settings", tooltip = {"networks-window.settings-tooltip"} }
      btn.style.top_margin = 2
      return flow
    end,
    populate = function(el, nwd, pt)
      if not (el and el.valid) then return end
      -- Tag the buttons so click handler can find the network
      for _, btn in ipairs(el.children) do
        if btn and btn.valid and btn.type == "sprite-button" then
          local has_players = network_data.players_in_network(nwd) > 0
          if btn.name:find("trash", 1, true) then
            btn.enabled = not has_players -- Disable if players are using it
          end
          btn.tags = { network_id = nwd.id or 0 }
          if btn.name:find("settings", 1, true) then
            btn.toggled = nwd.id and (nwd.id == pt.settings_network_id) -- Highlight if this is the settings network
          end
        end
      end
    end
  },
}

--- Create the Networks window for a player
--- @param player LuaPlayer
function networks_window.create(player)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end

  player_data.register_ui(player_table, "networks")

  -- Destroy existing instance first
  if player.gui.screen[WINDOW_NAME] then
    player.gui.screen[WINDOW_NAME].destroy()
  end

  -- The main Networks window
  local window = player.gui.screen.add{ type = "frame", name = WINDOW_NAME, direction = "vertical", style = "li_window_style", visible = player_table.networks_window_visible }

    -- Title bar with dragger and close
    local titlebar = window.add{ type = "flow", style = "fs_flib_titlebar_flow", name = WINDOW_NAME .. "-titlebar", drag_target = window }

      local label = titlebar.add{ type = "label", name = WINDOW_NAME .. "-caption", caption = {"networks-window.window-title"}, style = "frame_title", ignored_by_interaction = true }
      label.style.top_margin = -4
      titlebar.add {type = "empty-widget", style = "fs_flib_titlebar_drag_handle", ignored_by_interaction = true }
      titlebar.add({ type = "sprite-button", style = "frame_action_button", sprite = "utility/close", name = WINDOW_NAME .. "-close", tooltip = {"networks-window.close-window-tooltip"}, drag_target = window })
      titlebar.drag_target = window

    -- Split: Content and settings, with settings being invisible until player asks for them
    local outside_flow = window.add{ type = "flow", name = WINDOW_NAME.."-outside", direction = "horizontal" }

      -- Content: scrollable table to align uneven-width data
      local content_frame = outside_flow.add{ type = "frame", name = WINDOW_NAME.."-inside", style = "inside_shallow_frame", direction = "vertical" }
        local subheader_frame = content_frame.add{ type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "horizontal" }
        subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
        subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
        -- Scrollable area for the data table
          local scroll = subheader_frame.add{ type = "scroll-pane", style = "naked_scroll_pane", name = WINDOW_NAME .. "-scroll", horizontal_scroll_policy = "never" }
          scroll.style.padding = 2

          local col_count = #cell_setup
          local table_el = scroll.add{ type = "table", name = WINDOW_NAME .. "-table", column_count = col_count, draw_horizontal_lines = true, draw_horizontal_line_after_headers = true, draw_vertical_lines = false }
          table_el.style.horizontal_spacing = 6
          table_el.style.vertical_spacing = 4
          -- Set column alignments as configured
          for idx, col in ipairs(cell_setup) do
            if col.align then
              table_el.style.column_alignments[idx] = col.align
            end
          end

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

      -- Settings: Frame for settings to be shown
      local settings_frame = outside_flow.add{ type = "frame", name = WINDOW_NAME.."-settings", style = "inside_shallow_frame", direction = "vertical" }
      network_settings.create_frame(settings_frame, player)
      settings_frame.visible = false
      player_table.settings_network_id = nil

  -- Remember this for easy access
  player_table.ui.networks.subheader_frame = subheader_frame -- To resize
  player_table.ui.networks.table_elements = table_el -- To update content
  player_table.ui.networks.settings_frame = settings_frame -- For settings

  if player_table and player_table.networks_window_location then
    window.location = player_table.networks_window_location
  else
    window.location = { x = 300, y = 100 }
  end
  -- Update the content now so the window can size itself properly before being shown
  networks_window.update(player)
end

-- When the window is moved, remember its new location
function networks_window.gui_location_moved(element, player_table)
  if element.name == WINDOW_NAME and player_table then
    if not player_table.networks_window_location then
      player_table.networks_window_location = {}
    end
    player_table.networks_window_location.x = element.location.x
    player_table.networks_window_location.y = element.location.y
  end
end

--- Destroy the Networks window for a player
--- @param player LuaPlayer
function networks_window.destroy(player)
  if not player or not player.valid then return end
  local w = player.gui.screen[WINDOW_NAME]
  if w then w.destroy() end

  local player_table = player_data.get_player_table(player.index)
  if player_table and player_table.ui and player_table.ui.networks then
    player_table.ui.networks.table_elements = nil
  end
end

--- Set visibility of the Networks window
--- @param player LuaPlayer The player whose window to toggle
--- @param player_table PlayerData The player's data table
--- @param visible boolean Whether the window should be visible
function networks_window.set_window_visible(player, player_table, visible)
  if not player or not player.valid or not player_table then return end
  player_table.networks_window_visible = not visible
  networks_window.toggle_window_visible(player)
  if player_table.networks_window_visible ~= visible then
    networks_window.toggle_window_visible(player)
  end
end

--- Toggle visibility of the Networks window
--- @param player LuaPlayer
function networks_window.toggle_window_visible(player)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  local w = player.gui.screen[WINDOW_NAME]
  if not w then
    player_table.networks_window_visible = true
    networks_window.create(player)
    return
  end
  w.visible = not w.visible
  player_table.networks_window_visible = w.visible
end

---@param player_table? PlayerData
local function close_settings_pane(player_table)
  if not player_table or not player_table.ui or not player_table.ui.networks then return end
  player_table.settings_network_id = nil
  player_table.ui.networks.settings_frame.visible = false
end

--- Ensure the Networks table has exactly `count` data rows (below the header).
--- Rows are created with placeholder cells so they can be filled later without resizing.
--- @param player LuaPlayer
--- @param count integer Number of networks to show data for
function networks_window.update_network_count(player, count)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table or not player_table.networks_window_visible then
    close_settings_pane(player_table)
    return
  end

  if not player_table or not player_table.ui or not player_table.ui.networks then return end
  if count < 0 then count = 0 end

  local table_el = player_table.ui.networks.table_elements
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
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end
  if not player_table.networks_window_visible then
    return
  end
  if not player_table.ui or not player_table.ui.networks then
    networks_window.create(player)
    return -- Will update on the next call
  end
  -- Debug
  -- local win = player.gui.screen["li_networks_window"]
  -- if win then
  --   local lbl = win["li_networks_window-titlebar"].children[1]
  --   if lbl then
  --     lbl.caption = "(x,y) " .. tostring(win.location.x) .. ", " .. tostring(win.location.y)
  --   end
  -- end

  local table_el = player_table.ui.networks.table_elements

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

  local seen_settings_network = false
  for i, nw in ipairs(list) do
    for _, col in ipairs(cell_setup) do
      local name = string.format("%s-cell-%d-%s", WINDOW_NAME, i, col.key)
      local el = table_el[name]
      if col.populate then
        col.populate(el, nw, player_table)
      end
    end
    if nw.id == player_table.settings_network_id then
      seen_settings_network = true
    end
  end

  -- Update settings frame
  if seen_settings_network then
    network_settings.update(player, player_table)
  elseif player_table.settings_network_id then
    close_settings_pane(player_table)
  end
end

--- Handle clicks on Networks window mini buttons (settings/trash).
--- Returns "refresh", "openmain" or nil
---@param event EventData.on_gui_click
---@return string|nil nil if no action, "refresh" is the UI needs refreshing, and "openmain" if the main window should be opened
function networks_window.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return nil end
  local name = element.name or ""
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return nil end

  if player and (name == WINDOW_NAME .. "-close") then
    networks_window.toggle_window_visible(player)
    return nil
  end

  -- Only handle Action buttons
  if not name:find(WINDOW_NAME .. "-cell-", 1, true) then return nil end

  -- Identify column from the control name
  local row_str, col_key = name:match(WINDOW_NAME .. "%-cell%-(%d+)%-actions%-(%w+)$")
  if not col_key or (col_key ~= "settings" and col_key ~= "trash" and col_key ~= "view") then
    return nil
  end

  -- Resolve the network id: prefer tags; fallback to row index lookup
  if element.tags then
    local network_id = tonumber(element.tags.network_id)
    local networkdata = network_data.get_networkdata_fromid(network_id)
    local network = networkdata and network_data.get_LuaNetwork(networkdata)
    local player_table = player_data.get_player_table(event.player_index)

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
      return "openmain"
    elseif col_key == "settings" and network_id and player_table then
      -- Show/hide settings for this network
      local is_open = player_table.ui.networks.settings_frame.visible
      if is_open then
        if player_table.settings_network_id == network_id then
          close_settings_pane(player_table)
        else
          -- Opening settings for this (new) network
          player_table.settings_network_id = network_id
        end
      else
        -- Open the window on the selected network
        player_table.settings_network_id = network_id
        player_table.ui.networks.settings_frame.visible = true
      end
      networks_window.update(player)
      return nil
    elseif col_key == "trash" and network_id and player_table then
      -- Remove the network from storage
      if network_data.remove_network(network_id) then
        if player_table.settings_network_id == network_id then
          close_settings_pane(player_table)
        end
        -- Update the window after removal
        networks_window.update(player)
      end
    end
  end
  return nil
end

return networks_window
