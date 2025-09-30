--- Settings for a single network

local network_settings = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"

local WINDOW_NAME = "li_network_settings_window"
local WINDOW_MIN_HEIGHT = 110-3*24 
local WINDOW_MAX_HEIGHT = 110+10*24 
local clear_mismatched_storage_action="clear-mismatch-storage-list"
local clear_undersupply_ignore_list_action="clear-undersupply-ignore-list"
local ignore_higher_quality_matches_setting="ignore-higher-quality-mismatches"
local ignore_buffer_chests_setting="ignore-buffer-chests"

-- Add a Network ID header line
---@param ui LuaGuiElement The parent UI element to add the header to
---@param player_table PlayerData The player's data table
local function add_network_id_header(ui, player_table)
  if not ui or not ui.valid then return nil end

  local header = ui.add{type="label", caption={"network-settings.window-title", 0}, style="bold_label"}
  player_table.ui.network_settings.network_id_header = header
end

-- Add a header line to indicate a section of settings beginning
---@returns LuaGuiElement|nil
local function add_settings_header(ui, caption)
  if not ui or not ui.valid then return nil end

  local header = ui.add{type="label", caption=caption, style="caption_label"}
  return header
end

-- Add a checkbox setting
---@param ui LuaGuiElement The parent UI element to add the header to
---@param setting_name string The name of the setting (used for localization keys and element names)
---@param default_state boolean The default state of the checkbox
local function add_checkbox_setting(ui, setting_name, default_state)
  if not ui or not ui.valid or not setting_name then return end

  local checkbox = ui.add{type="checkbox", name="li_"..setting_name, 
    caption={"network-settings."..setting_name}, tooltip={"network-settings."..setting_name.."-tooltip"}, tags={action=setting_name}, state=default_state}
  return checkbox
end

-- Add a setting that has a text label and a Clear button, referring to a list of things
---@param ui LuaGuiElement The parent UI element to add the setting to
---@param caption LocalisedString The caption for the setting
---@param action_name string The action tag to associate with the Clear button
-- Add a setting that has a descriptive name and a Clear button
local function add_setting_with_clear_button(ui, caption, action_name)
  if not ui or not ui.valid or not caption then return end

  local setting_flow = ui.add{type="flow", direction="horizontal"}
  setting_flow.style.horizontal_spacing = 8
  local label = setting_flow.add{type="label", style="label", name=action_name.."-label", caption={caption, 0}, tooltip={caption.."-tooltip"}, tags={caption_key=caption}}
  label.style.top_margin = 4
  local space = setting_flow.add {type = "empty-widget", style = "draggable_space"}
  space.style.horizontally_stretchable = true
  local button = setting_flow.add{type="button", style="other_settings_gui_button", name=action_name.."-clear", tags={action=action_name}, caption={"network-settings.clear-list-button"}}
  button.enabled = false
  return setting_flow
end

-- Add all suggestions-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_suggestions_settings(ui, player_table)
  if not ui or not ui.valid then return end

  local setting_flow = ui.add{type="flow", direction="horizontal"}
  local vflow = setting_flow.add {type = "flow", direction = "vertical"}

  add_settings_header(vflow, {"network-settings.mismatched-storage-header"})
  local checkbox = add_checkbox_setting(vflow, ignore_higher_quality_matches_setting, false)
  player_table.ui.network_settings.ignore_higher_quality_mismatches = checkbox
  local flow = add_setting_with_clear_button(vflow, "network-settings.chests-on-ignore-list", clear_mismatched_storage_action)
  player_table.ui.network_settings.mismatched_storage_flow = flow
end

-- Add all Undersupply-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_undersupply_settings(ui, player_table)
  if not ui or not ui.valid then return end

  local setting_flow = ui.add{type="flow", direction="horizontal", name="undersupply_h"}
  local vflow = setting_flow.add {type = "flow", direction = "vertical", name="undersupply_v"}

  add_settings_header(vflow, {"network-settings.undersupply-header"})
  -- Add ignore buffer chests setting
  local ignore_buffer_checkbox = add_checkbox_setting(vflow, ignore_buffer_chests_setting, false)
  player_table.ui.network_settings.ignore_buffer_chests = ignore_buffer_checkbox
  local flow = add_setting_with_clear_button(vflow, "network-settings.items-on-undersupply-ignore-list", clear_undersupply_ignore_list_action)
  player_table.ui.network_settings.ignored_undersupply_items = flow
end

--- Create settings window
---@param parent LuaGuiElement The parent element to create the settings window in
---@param player? LuaPlayer
function network_settings.create_frame(parent, player)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end

  player_data.register_ui(player_table, "network_settings")

  local window = parent.add {type = "frame", name = WINDOW_NAME, direction = "vertical", style = "li_window_style"}

    -- Content: Area to host settings for the network
    local inside_frame = window.add{type = "frame", name = WINDOW_NAME.."-inside", style = "inside_deep_frame", direction = "vertical"}
      inside_frame.style.vertically_stretchable = true
      inside_frame.style.horizontally_stretchable = true
      local subheader_frame = inside_frame.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.vertically_stretchable = true

    -- Add actual settings
    add_network_id_header(subheader_frame, player_table)
    add_suggestions_settings(subheader_frame, player_table)
    add_undersupply_settings(subheader_frame, player_table)
end

local function update_setting_with_clear_button(setting_flow, action_name, count)
  if not setting_flow or not setting_flow.valid then return end

  local label = setting_flow[action_name.."-label"]
  if label and label.valid then
    local key = label.tags and label.tags.caption_key or (label.caption and label.caption[1])
    label.caption = { key, count }
  end

  local button = setting_flow[action_name.."-clear"]
  if button and button.valid then
    button.enabled = (count > 0)
  end
end

-- Update the settings UI to reflect current settings
---@param player? LuaPlayer
---@param player_table PlayerData
function network_settings.update(player, player_table)
  if not player or not player.valid or not player_table then return end
  if not player_table.ui or not player_table.ui.network_settings then return end

  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return end

  -- Update network ID in title
  local header = player_table.ui.network_settings.network_id_header
  if header then
    header.caption = {"network-settings.window-title", network_id or 0}
  end

  -- Update Suggestions settings
  player_table.ui.network_settings.ignore_higher_quality_mismatches.state = networkdata.ignore_higher_quality_mismatches
  local flow = player_table.ui.network_settings.mismatched_storage_flow
  local count = networkdata and table_size(networkdata.ignored_storages_for_mismatch) or 0
  update_setting_with_clear_button(flow, clear_mismatched_storage_action, count)

  -- Update Undersupply settings
  -- Update ignore buffer chests setting
  if player_table.ui.network_settings.ignore_buffer_chests then
    player_table.ui.network_settings.ignore_buffer_chests.state = networkdata.ignore_buffer_chests_for_undersupply or false
  end
  flow = player_table.ui.network_settings.ignored_undersupply_items
  count = networkdata and table_size(networkdata.ignored_items_for_undersupply) or 0
  update_setting_with_clear_button(flow, clear_undersupply_ignore_list_action, count)
end

local function adopt_checkbox_state(event)
  local player_table = player_data.get_player_table(event.player_index)
  if not player_table then return false end

  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if event.element.tags.action == ignore_higher_quality_matches_setting then
    networkdata.ignore_higher_quality_mismatches = player_table.ui.network_settings.ignore_higher_quality_mismatches.state
  elseif event.element.tags.action == ignore_buffer_chests_setting then
    networkdata.ignore_buffer_chests_for_undersupply = player_table.ui.network_settings.ignore_buffer_chests.state
  end

  -- Update UI
  local player = game.get_player(event.player_index)
  network_settings.update(player, player_table)
end

-- Clear the relevant list and refresh the window to show the effect
local function clear_list_and_refresh(event)
  local player_table = player_data.get_player_table(event.player_index)
  if not player_table then return false end

  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if event.element.tags.action == clear_mismatched_storage_action then
    -- Clear the list of ignored storages for mismatched storage suggestion
    networkdata.ignored_storages_for_mismatch = {}
  elseif event.element.tags.action == clear_undersupply_ignore_list_action then
    -- Clear the list of ignored storages for undersupply
    networkdata.ignored_items_for_undersupply = {}
  end

  -- Update UI
  local player = game.get_player(event.player_index)
  network_settings.update(player, player_table)
end

---@returns boolean true if the click was handled
function network_settings.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if not event.element.tags then return false end

  if event.element.tags.action == ignore_higher_quality_matches_setting or event.element.tags.action == ignore_buffer_chests_setting then
    adopt_checkbox_state(event)
  elseif event.element.tags.action == clear_mismatched_storage_action or event.element.tags.action == clear_undersupply_ignore_list_action then
    clear_list_and_refresh(event)
  else
    return false
  end
  return true
end


return network_settings