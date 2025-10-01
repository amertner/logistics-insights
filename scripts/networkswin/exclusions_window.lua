--- Manage lists of per-network exclusion lists: Show items and allow items to be deleted.
local exclusions_window = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"
local utils = require "scripts.utils"

local WINDOW_NAME = "li_exclusions_list_window"
local WINDOW_MIN_HEIGHT = 110-3*24
local WINDOW_MAX_HEIGHT = 110+10*24

exclusions_window.chests_on_ignore_list_setting = "chests-on-ignore-list"
exclusions_window.undersupply_ignore_list_setting = "items-on-undersupply-ignore-list"

-- Add a Network ID header line
---@param ui LuaGuiElement The parent UI element to add the header to
---@param player_table PlayerData The player's data table
local function add_list_header(ui, player_table)
  local header = ui.add{type="label", caption={"exclusions-window.window-title"}, style="bold_label"}
  header.style.left_margin = 4
  header.style.top_margin = 4
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

  local window = parent.add {type = "frame", name = WINDOW_NAME, direction = "vertical", style = "li_window_style"}

    -- Header: Network ID and Revert to defaults button
      local header_frame = window.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "inside_deep_frame"}
      local header_flow = header_frame.add{type="flow", direction="horizontal"}
      add_list_header(header_flow, player_table)

    -- Content: Area to host settings for the network
    local inside_frame = window.add{type = "frame", name = WINDOW_NAME.."-inside", style = "inside_deep_frame", direction = "vertical"}
      inside_frame.style.vertically_stretchable = true
      inside_frame.style.horizontally_stretchable = true
      local subheader_frame = inside_frame.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.vertically_stretchable = true

    -- Table for exclusions
    local exclusions_table = subheader_frame.add{type = "table", name = WINDOW_NAME.."-table", column_count = 3, style = "li_mainwindow_content_style"}
    player_table.ui.exclusions_pane.exclusions_table = exclusions_table

end

---@param gui_table LuaGuiElement The GUItable to contain the list
---@param list table<string, boolean>
local function show_item_quality_list(gui_table, list)
  for item_quality, excluded in pairs(list) do
    local item_name, quality_name = string.match(item_quality, "^(.-):(.*)$")
    if item_name and quality_name and excluded then
      local cell = gui_table.add {name = "li-exclude-"..item_quality, type = "sprite-button", style = "slot_button"}
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
---@param excluded_numbers table<number, boolean>
---@param player_table PlayerData
local function show_storage_item_list(gui_table, excluded_numbers, player_table)
  local entity_list = {}
  for _, chest in pairs(player_table.network.storages) do
    if chest and chest.valid and excluded_numbers[chest.unit_number] then
      table.insert(entity_list, chest)
    end
  end

  for _, chest in pairs(entity_list) do
    if chest and chest.valid then
      local cell = gui_table.add {type = "sprite-button", style = "slot_button"}
      local filter = get_filter_for_chest(chest)
      if filter then
        cell.sprite = utils.get_valid_sprite_path("item/", filter.name)
        cell.quality = filter.quality or "normal"
      else
        cell.sprite = "item/storage-chest"
      end
      --cell.caption = tostring(chest.unit_number)
    end
  end
end

-- ignored_storages_for_mismatch table<number, boolean>
-- ignored_items_for_undersupply table<string, boolean> -- A list of "item name:quality" to ignore for undersupply suggestion

---@param player_table PlayerData
function exclusions_window.update(player_table)
   if not player_table.ui.networks.exclusions_frame.visible then return end

  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return end
  local setting_shown = player_table.exclusion_list_shown

  if setting_shown then
    player_table.ui.exclusions_pane.header.caption = {"exclusions-window."..setting_shown.."-headline"}
  else
    player_table.ui.exclusions_pane.header.caption = {"exclusions-window.window-title"}
  end

  exclusions_table = player_table.ui.exclusions_pane.exclusions_table
  if not exclusions_table then return end

  -- Clear existing entries
  exclusions_table.clear()

  if setting_shown == exclusions_window.undersupply_ignore_list_setting then
    show_item_quality_list(exclusions_table, networkdata.ignored_items_for_undersupply)
  elseif player_table.exclusion_list_shown == exclusions_window.chests_on_ignore_list_setting then
    show_storage_item_list(exclusions_table, networkdata.ignored_storages_for_mismatch, player_table)
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

return exclusions_window