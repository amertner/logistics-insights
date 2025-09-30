--- Settings for a single network

local network_settings = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"

local WINDOW_NAME = "li_network_settings_window"
local WINDOW_MIN_HEIGHT = 110-3*24
local WINDOW_MAX_HEIGHT = 110+10*24
local clear_mismatched_storage_action="chests-on-ignore-list"
local clear_undersupply_ignore_list_action="items-on-undersupply-ignore-list"
local ignore_higher_quality_matches_setting="ignore-higher-quality-mismatches"
local ignore_buffer_chests_setting="ignore-buffer-chests"
local revert_to_defaults_button_name="network-settings-revert-to-defaults"

---@class NetworkSettingControls
---@field revert LuaGuiElement The revert button for this setting
---@field control LuaGuiElement The main control (checkbox, button, etc)
---@field default any The default value for this setting

-- Add a Network ID header line
---@param ui LuaGuiElement The parent UI element to add the header to
---@param player_table PlayerData The player's data table
local function add_network_id_header(ui, player_table)
  local header = ui.add{type="label", caption={"network-settings.window-title", 0}, style="bold_label"}
  header.style.left_margin = 4
  header.style.top_margin = 4
  player_table.ui.network_settings.network_id_header = header
end

-- Add a header line to indicate a section of settings beginning
---@returns LuaGuiElement Returns the table that will contain the settings
local function add_settings_header(ui, caption)
  ui.add{type="label", caption=caption, style="caption_label"}
  local settings_table = ui.add{type="table", column_count=2}
  return settings_table
end

-- Add a flow containing a revert button and a label with a tooltip
---@param table LuaGuiElement The parent UI element to add the header to
---@param setting_name string The name of the setting (used for localization keys and element names)
---@returns LuaGuiElement The revert button created
local function add_label_with_revert_button(table, setting_name)
  local hflow = table.add{type="flow", direction="horizontal"}
  local revert_button = hflow.add {type="sprite-button", style="mini_tool_button_red", sprite="utility/reset_white", tooltip={"network-settings.setting-has-default-value"}, tags={name=setting_name, action="revert"}}
  revert_button.enabled = false
  hflow.add{type="label", style="label", caption={"network-settings."..setting_name}, tooltip={"network-settings."..setting_name.."-tooltip"}}
  return revert_button
end

-- Add a checkbox setting
---@param table LuaGuiElement The parent UI element to add the header to
---@param setting_name string The name of the setting (used for localization keys and element names)
---@param default_state boolean The default state of the checkbox
---@returns NetworkSetting
local function add_checkbox_setting(table, setting_name, default_state)
  local revert = add_label_with_revert_button(table, setting_name)
  local checkbox = table.add{type="checkbox", name="li_"..setting_name, tags={name=setting_name, action="set"}, state=default_state}
  return {revert = revert, control = checkbox, default=default_state}
end

-- Add a setting that has a text label and a Clear button, referring to a list of things
---@param table LuaGuiElement The parent table element to add the setting to
---@param setting_name string The caption for the setting
---@returns NetworkSetting
local function add_setting_with_list(table, setting_name)
  local revert = add_label_with_revert_button(table, setting_name)
  local label = table.add{type="label", style="label", caption="0"}

  return {revert = revert, control = label, default=0}
end

-- Add all suggestions-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_suggestions_settings(ui, player_table)
  local settings_table = add_settings_header(ui, {"network-settings.mismatched-storage-header"})

  local setting = add_checkbox_setting(settings_table, ignore_higher_quality_matches_setting, false)
  player_table.ui.network_settings[ignore_higher_quality_matches_setting] = setting

  setting = add_setting_with_list(settings_table, clear_mismatched_storage_action)
  player_table.ui.network_settings[clear_mismatched_storage_action] = setting
end

-- Add all Undersupply-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_undersupply_settings(ui, player_table)
  local settings_table = add_settings_header(ui, {"network-settings.undersupply-header"})
  
  -- Add ignore buffer chests setting
  local setting = add_checkbox_setting(settings_table, ignore_buffer_chests_setting, false)
  player_table.ui.network_settings[ignore_buffer_chests_setting] = setting
  setting = add_setting_with_list(settings_table, clear_undersupply_ignore_list_action)
  player_table.ui.network_settings[clear_undersupply_ignore_list_action] = setting
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

    -- Header: Network ID and Revert to defaults button
      local header_frame = window.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "inside_deep_frame"}
      local header_flow = header_frame.add{type="flow", direction="horizontal"}
      add_network_id_header(header_flow, player_table)
      local space = header_flow.add {type = "empty-widget"}
      space.style.horizontally_stretchable = true
      local default_settings = header_flow.add{type="sprite-button", style="tool_button_red", name=revert_to_defaults_button_name, sprite="utility/reset", tooltip={"network-settings.all-options-default-tooltip"}}
      player_table.ui.network_settings.defaults_button = default_settings

    -- Content: Area to host settings for the network
    local inside_frame = window.add{type = "frame", name = WINDOW_NAME.."-inside", style = "inside_deep_frame", direction = "vertical"}
      inside_frame.style.vertically_stretchable = true
      inside_frame.style.horizontally_stretchable = true
      local subheader_frame = inside_frame.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.vertically_stretchable = true

    -- Add actual settings
    add_suggestions_settings(subheader_frame, player_table)
    add_undersupply_settings(subheader_frame, player_table)
end

---@param control NetworkSettingControls
---@param is_changed boolean True if the setting is changed from default
---@param changed_tooltip LocalisedString|nil Optional tooltip to use when setting is changed
local function update_revert_button(control, is_changed, changed_tooltip)
  if control.revert and control.revert.valid then
    control.revert.enabled = is_changed
    if is_changed then
      if changed_tooltip then
        control.revert.tooltip = changed_tooltip
      else
        control.revert.tooltip = {"network-settings.reset-setting-to-default-tooltip", control.default}
      end
      control.revert.sprite = "utility/reset"
    else
      control.revert.tooltip = {"network-settings.setting-has-default-value"}
      control.revert.sprite = "utility/reset_white"
    end
  end
end

---@param control NetworkSettingControls
---@param count number The number of items in the list this setting refers to
local function update_list_setting(control, count)
  local changed = 0
  if count > 0 then
    changed = 1
  end

  update_revert_button(control, changed > 0, {"network-settings.reset-list-setting"})
  control.control.caption = tostring(count)
  return changed
end

---@param control NetworkSettingControls
---@param state boolean
---@return number Return number of settings changed (0 or 1)
function update_checkbox_setting(control, state)
  local changed = 0
  if state ~= control.default then
    changed = 1
  end
  update_revert_button(control, changed > 0)
  if control.control and control.control.valid then
    control.control.state = state
  end
  return changed
end

--- Update the settings UI to reflect current settings
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

  -- Iterate over all settings and update them
  local num_changed = 0 -- Number of settings that are not the default
  for name, control in pairs(player_table.ui.network_settings) do
    if name == ignore_higher_quality_matches_setting then
      num_changed = num_changed + update_checkbox_setting(control, networkdata.ignore_higher_quality_mismatches)
    elseif name == ignore_buffer_chests_setting then
      num_changed = num_changed + update_checkbox_setting(control, networkdata.ignore_buffer_chests_for_undersupply)
    elseif name == clear_mismatched_storage_action then
      num_changed = num_changed + update_list_setting(control, table_size(networkdata.ignored_storages_for_mismatch))
    elseif name == clear_undersupply_ignore_list_action then
      num_changed = num_changed + update_list_setting(control, table_size(networkdata.ignored_items_for_undersupply))
    end
  end
  local defaults_button = player_table.ui.network_settings.defaults_button
  if defaults_button and defaults_button.valid then
    if num_changed == 0 then
      defaults_button.enabled = false
      defaults_button.tooltip = {"network-settings.all-options-default-tooltip"}
    else
      defaults_button.enabled = true
      defaults_button.tooltip = {"network-settings.revert-N-options-to-defaults-tooltip", num_changed}
    end
  end
end

---@param player_table PlayerData
---@param name string
---@param setting NetworkSettingControls
local function set_checkbox_setting(player_table, name, action, setting)
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  local new_value
  if action == "revert" then
    new_value = setting.default
  else
    new_value = setting.control.state
  end
  if name == ignore_higher_quality_matches_setting then
    networkdata.ignore_higher_quality_mismatches = new_value
  elseif name == ignore_buffer_chests_setting then
    networkdata.ignore_buffer_chests_for_undersupply = new_value
  else
    return false
  end
end

-- Clear the relevant list and refresh the window to show the effect
local function clear_list_and_refresh(player_table, event)
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if event.element.tags.name == clear_mismatched_storage_action then
    -- Clear the list of ignored storages for mismatched storage suggestion
    networkdata.ignored_storages_for_mismatch = {}
  elseif event.element.tags.name == clear_undersupply_ignore_list_action then
    -- Clear the list of ignored storages for undersupply
    networkdata.ignored_items_for_undersupply = {}
  end
end

local function revert_to_defaults(player_table, event)
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if networkdata then
    networkdata.ignore_higher_quality_mismatches = false
    networkdata.ignore_buffer_chests_for_undersupply = false
    networkdata.ignored_storages_for_mismatch = {}
    networkdata.ignored_items_for_undersupply = {}
  end
end

--- Handle clicks
---@returns boolean true if the click was handled
function network_settings.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if not event.element.tags then return false end

  local handled = false
  local player_table = player_data.get_player_table(event.player_index)
  if player_table then
    local setting_name = event.element.tags.name
    local action = event.element.tags.action
    local controls = player_table.ui.network_settings[setting_name]
    if controls then
      if controls.control and controls.control.valid then
        if controls.control.type == "checkbox" then
          set_checkbox_setting(player_table, setting_name, action, controls)
          handled = true
        end
        if action == "revert" and controls.control.type == "label" then
          -- Revert button for a list setting
          if setting_name == clear_mismatched_storage_action or setting_name == clear_undersupply_ignore_list_action then
            clear_list_and_refresh(player_table, event)
            handled = true
          end
        end
      end
    end

    if event.element.name == revert_to_defaults_button_name then
      revert_to_defaults(player_table, event)
      handled = true
    end
    if handled then
      local player = game.get_player(player_table.player_index)
      network_settings.update(player, player_table)      
    end
  end
  return handled
end


return network_settings