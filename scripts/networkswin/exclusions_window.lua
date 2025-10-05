--- Manage lists of per-network exclusion lists: Show items and allow items to be deleted.
local exclusions_window = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"
local find_and_highlight = require "scripts.mainwin.find_and_highlight"
local utils = require "scripts.utils"

local WINDOW_NAME = "li-exclusions-frame"
local WINDOW_HEIGHT = 210

exclusions_window.chests_on_ignore_list_setting = "chests-on-ignore-list"
exclusions_window.undersupply_ignore_list_setting = "items-on-undersupply-ignore-list"

-- Add a Network ID header line
---@param ui LuaGuiElement The parent UI element to add the header to
---@param player_table PlayerData The player's data table
local function add_list_header(ui, player_table)
  local header = ui.add{type="label", caption={"exclusions-window.window-title"}, style="bold_label"}
  header.style.left_margin = 4
  player_table.ui.exclusions_pane.header = header
end

--- Create settings window
---@param parent LuaGuiElement The parent element to create the settings window in
---@param player? LuaPlayer
function exclusions_window.create_frame(parent, player)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end

  player_data.register_ui(player_table, "exclusions_pane")

  local window = parent.add {type = "frame", name = WINDOW_NAME, direction = "vertical", style = "inside_shallow_frame"}
  local column_count = player_table.settings.max_items - 4

  local subheader_frame = window.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
  subheader_frame.style.minimal_width = 40 * column_count + 16 + 8
  subheader_frame.style.height = WINDOW_HEIGHT

    --local header_frame = window.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "inside_deep_frame"}
    local header_flow = subheader_frame.add{type="flow", direction="horizontal",  name = WINDOW_NAME.."-header-flow"}
    add_list_header(header_flow, player_table)

    -- Table for exclusions
    local scroll = subheader_frame.add{ type = "scroll-pane", style = "naked_scroll_pane", name = WINDOW_NAME .. "-scroll", horizontal_scroll_policy = "never" }
    scroll.style.padding = 0
    local scrollflow = scroll.add{type="flow", direction="horizontal",  name = WINDOW_NAME.."-scroll-flow"}

    local exclusions_table = scrollflow.add{type = "table", name = WINDOW_NAME.."-table", column_count = column_count, style = "li_mainwindow_content_style"}

    local spacer = subheader_frame.add{type="empty-widget"}
    spacer.style.vertically_stretchable = true

    player_table.ui.exclusions_pane.exclusions_table = exclusions_table
end

---@param gui_table LuaGuiElement The GUItable to contain the list
---@param list table<string, boolean>
local function show_item_quality_list(gui_table, list)
  for item_quality, excluded in pairs(list) do
    local item_name, quality_name = string.match(item_quality, "^(.-):(.*)$")
    if item_name and quality_name and excluded then
      local cell = gui_table.add {name = "li-exclude-"..item_quality, type = "sprite-button", style = "slot_button", 
        tooltip={"exclusions-window.remove-undersupply-exclusion-tooltip"},
        tags={item_name=item_name, quality=quality_name, shift_action="remove-undersupply", pane=WINDOW_NAME}}
      cell.sprite = utils.get_valid_sprite_path("item/", item_name)
      cell.quality = quality_name or "normal"
    end
  end
end

--- Return the filter on a chest, if it has one. If multiple, return the first one
---@param chest LuaEntity|nil
---@return table<string, string>|nil {name=string, quality=string}|nil
local function get_filter_for_chest(chest)
  if not chest then return nil end

  if chest.filter_slot_count > 0 then
    local filter = chest.get_filter(1)
    if filter then
      local fname = filter.name and (filter.name.name or filter.name) or nil
      if fname then
        local fqual = filter.quality and (filter.quality.name or filter.quality) or nil
        return {name = fname, quality = fqual or "normal"}
      end
    end
  end
  return nil
end

---@param gui_table LuaGuiElement The GUItable to contain the list
---@param networkdata LINetworkData
---@param player_table PlayerData
local function show_ignored_storages_for_mismatch_list(gui_table, networkdata, player_table)
  if not networkdata or not networkdata.ignored_storages_for_mismatch or not player_table or not player_table.network or not player_table.network.valid then return end
  if player_table.ignored_storages_for_mismatch_shown >= networkdata.ignored_storages_for_mismatch_changed then
    return -- No change since last shown
  end
  exclusions_table.clear()
  player_table.ignored_storages_for_mismatch_shown = game.tick
  local excluded_numbers = networkdata.ignored_storages_for_mismatch
  local entity_list = {}
  for _, chest in pairs(player_table.network.storages) do
    if chest and chest.valid and excluded_numbers[chest.unit_number] then
      table.insert(entity_list, chest)
    end
  end

  for _, chest in pairs(entity_list) do
    if chest and chest.valid then
      local cell = gui_table.add {type = "sprite-button", style = "slot_button", 
        tooltip={"exclusions-window.filter-exclusion-tooltip"},
        tags={entity_id=chest.unit_number, action="focus-chest", shift_action="remove-chest", pane=WINDOW_NAME}}
      local filter = get_filter_for_chest(chest)
      if filter then
        cell.sprite = utils.get_valid_sprite_path("item/", filter.name)
        cell.quality = filter.quality or "normal"
      else
        cell.sprite = "item/storage-chest"
      end
    end
  end
end

-- ignored_storages_for_mismatch table<number, boolean>
-- ignored_items_for_undersupply table<string, boolean> -- A list of "item name:quality" to ignore for undersupply suggestion

---@param player_table PlayerData
function exclusions_window.update(player_table)
   if not player_table or not player_table.ui or not player_table.ui.network_settings or not player_table.ui.network_settings.exclusions_frame then return end
   if not player_table.ui.network_settings.exclusions_frame.visible then return end

  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  local setting_shown = player_table.exclusion_list_shown

  exclusions_table = player_table.ui.exclusions_pane.exclusions_table
  if not exclusions_table then return end

  if setting_shown and networkdata then
    player_table.ui.exclusions_pane.header.caption = {"exclusions-window."..setting_shown.."-headline"}
  else
    player_table.ui.exclusions_pane.header.caption = ""-- {"exclusions-window.window-title"}
  end

  if not networkdata or not player_table.network or not player_table.network.valid then
    exclusions_table.clear()
    player_table.ignored_storages_for_mismatch_shown = 0
  else
    if setting_shown == exclusions_window.undersupply_ignore_list_setting then
      exclusions_table.clear()
      player_table.ignored_storages_for_mismatch_shown = 0
      show_item_quality_list(exclusions_table, networkdata.ignored_items_for_undersupply)
    elseif player_table.exclusion_list_shown == exclusions_window.chests_on_ignore_list_setting then
      show_ignored_storages_for_mismatch_list(exclusions_table, networkdata, player_table)
    end
  end
end

function exclusions_window.current_setting(player_table)
  return player_table.exclusion_list_shown
end

---@param player_table PlayerData
---@param setting_name string|nil
function exclusions_window.show_exclusions(player_table, setting_name)
  player_table.exclusion_list_shown = setting_name
  exclusions_window.update(player_table)
end

local function focus_on_chest(event)
  if not event.element or not event.element.valid then return false end
  local player_table = player_data.get_player_table(event.player_index)
  if not player_table or not player_table.network or not player_table.network.valid then return false end

  local tags = event.element.tags
  local entity_id = tags.entity_id
  local player = game.get_player(event.player_index)
  if player then
    local focus_chest = nil
    for _, chest in pairs(player_table.network.storages) do
      if chest and chest.valid and chest.unit_number == entity_id then
        focus_chest = chest
        break
      end
    end
    if focus_chest and focus_chest.valid then
      find_and_highlight.highlight_list_locations_on_map(player, {focus_chest}, true)
    end
  end
end

local function remove_chest_exclusion(event)
  if not event.element or not event.element.valid then return false end
  local player_table = player_data.get_player_table(event.player_index)
  if not player_table then return false end

  local tags = event.element.tags
  local entity_id = tags.entity_id
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if networkdata and networkdata.ignored_storages_for_mismatch then
    if entity_id and networkdata.ignored_storages_for_mismatch[entity_id] then
      network_data.remove_id_from_ignored_storages_for_mismatch(networkdata, entity_id)
      exclusions_window.update(player_table)
    end
  end
end

local function remove_undersupply_exclusion(event)
  if not event.element or not event.element.valid then return false end
  local player_table = player_data.get_player_table(event.player_index)
  if not player_table then return false end

  local tags = event.element.tags
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if networkdata and networkdata.ignored_items_for_undersupply then
    local key = utils.get_item_quality_key(tags.item_name, tags.quality)
    if networkdata.ignored_items_for_undersupply[key] then
      networkdata.ignored_items_for_undersupply[key] = nil
      exclusions_window.update(player_table)
    end
  end
end

---@returns boolean true if the click was handled
function exclusions_window.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if not event.element.tags then return false end
  if not event.element.tags.pane or event.element.tags.pane ~= WINDOW_NAME then return false end
  local handled = false
  -- Click = show item if possible
  -- Shift-click = remove item from ignore list

  local action = event.element.tags.action
  local shift_action = event.element.tags.shift_action

  if event.button == defines.mouse_button_type.left then
    if event.shift then
      if shift_action == "remove-undersupply" then
        remove_undersupply_exclusion(event)
        handled = true
      elseif shift_action == "remove-chest" then
        remove_chest_exclusion(event)
        handled = true
      end
    else
      if action == "focus-chest" then
        focus_on_chest(event)
        handled = true
      end
    end
  end

  return handled
end

return exclusions_window