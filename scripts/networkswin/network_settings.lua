--- Settings for a single network

local network_settings = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"
local exclusions_window = require "scripts.networkswin.exclusions_window"
local events = require "scripts.events"

local PANE_NAME = "li_network_settings_pane"
local WINDOW_MIN_HEIGHT = 110-3*24
local WINDOW_MAX_HEIGHT = 110+10*24
local mismatched_storage_setting=exclusions_window.chests_on_ignore_list_setting
local undersupply_ignore_list_setting=exclusions_window.undersupply_ignore_list_setting
local ignore_higher_quality_matches_setting="ignore-higher-quality-mismatches"
local ignore_buffer_chests_setting="ignore-buffer-chests"
local ignore_low_storage_when_no_storage_setting="ignore_low_storage_when_no_storage"
local revert_to_defaults_button_name="network-settings-revert-to-defaults"
local default_list_shown = mismatched_storage_setting

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
local function add_settings_header(ui, caption)
  ui.add{type="label", caption=caption, style="caption_label"}
  ui.add{type="empty-widget"}
end

-- Add a flow containing a revert button and a label with a tooltip
---@param table LuaGuiElement The parent UI element to add the header to
---@param setting_name string The name of the setting (used for localization keys and element names)
---@returns LuaGuiElement The revert button created
local function add_label_with_revert_button(table, setting_name)
  local hflow = table.add{type="flow", direction="horizontal"}
  local revert_button = hflow.add {type="sprite-button", style="mini_tool_button_red", sprite="utility/reset_white", tooltip={"network-settings.seting-has-default-value"}, 
    tags={name=setting_name, action="revert", pane=PANE_NAME}}
  revert_button.enabled = false
  revert_button.style.top_margin = 4
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
  local checkbox = table.add{type="checkbox", name="li_"..setting_name, tags={name=setting_name, action="set", pane=PANE_NAME}, state=default_state}
  return {revert = revert, control = checkbox, default=default_state}
end

-- Add a setting that has a text label and a Clear button, referring to a list of things
---@param table LuaGuiElement The parent table element to add the setting to
---@param setting_name string The caption for the setting
---@returns NetworkSetting
local function add_setting_with_list(table, setting_name, sprite_name)
  local revert = add_label_with_revert_button(table, setting_name)

  local button = table.add{type="sprite-button", style="frame_action_button", name="li_manage_"..setting_name, sprite=sprite_name, tooltip={"network-settings.manage-list-tooltip"}, 
    tags={name=setting_name, action="manage", pane=PANE_NAME}}

  return {revert = revert, control = button, default=0}
end

-- Add all suggestions-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_suggestions_settings(ui, player_table)
  add_settings_header(ui, {"network-settings.low-storage-header"})
  setting = add_checkbox_setting(ui, ignore_low_storage_when_no_storage_setting, false)
  player_table.ui.network_settings[ignore_low_storage_when_no_storage_setting] = setting

  local settings_table = add_settings_header(ui, {"network-settings.mismatched-storage-header"})

  local setting = add_checkbox_setting(ui, ignore_higher_quality_matches_setting, false)
  player_table.ui.network_settings[ignore_higher_quality_matches_setting] = setting
 
  setting = add_setting_with_list(ui, mismatched_storage_setting, "item/storage-chest")
  player_table.ui.network_settings[mismatched_storage_setting] = setting
end

-- Add all Undersupply-related settings
---@param ui LuaGuiElement The parent UI element to add the settings to
---@param player_table PlayerData The player's data table
local function add_undersupply_settings(ui, player_table)
  add_settings_header(ui, {"network-settings.undersupply-header"})
  
  -- Add ignore buffer chests setting
  local setting = add_checkbox_setting(ui, ignore_buffer_chests_setting, false)
  player_table.ui.network_settings[ignore_buffer_chests_setting] = setting
  setting = add_setting_with_list(ui, undersupply_ignore_list_setting, "item/requester-chest")
  player_table.ui.network_settings[undersupply_ignore_list_setting] = setting
end

--- Create settings window
---@param parent LuaGuiElement The parent element to create the settings window in
---@param player? LuaPlayer
function network_settings.create_frame(parent, player)
  if not player or not player.valid then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end

  player_data.register_ui(player_table, "network_settings")

  local window = parent.add {type = "flow", name = PANE_NAME, direction = "vertical"} --, style = "li_window_style"}
  window.style.padding = 0

    -- Header: Network ID and Revert to defaults button
      local header_frame = window.add{type = "frame", name = PANE_NAME.."-subheader", style = "inside_deep_frame"}
      local header_flow = header_frame.add{type="flow", direction="horizontal"}
      add_network_id_header(header_flow, player_table)
      local space = header_flow.add {type = "empty-widget"}
      space.style.horizontally_stretchable = true
      local default_settings = header_flow.add{type="sprite-button", style="tool_button_red", name=revert_to_defaults_button_name, sprite="utility/reset", tooltip={"network-settings.all-options-default-tooltip"},
        tags={action="revert-to-defaults", pane=PANE_NAME}}
      local close_button = header_flow.add({type="sprite-button", style="li_close_settings_button", sprite="utility/close", name=PANE_NAME.."-close", tooltip={"network-settings.close-window-tooltip"},
        tags={action="close", pane=PANE_NAME}})
      --close_button.style.top_margin = 2
      player_table.ui.network_settings.defaults_button = default_settings

    -- Content: Area to host settings for the network
    local outer_flow = window.add{type="flow", direction="horizontal"}
    outer_flow.style.padding = 0
    local inside_frame = outer_flow.add{type = "frame", name = PANE_NAME.."-inside", style = "inside_deep_frame", direction = "vertical"}
      inside_frame.style.vertically_stretchable = true
      inside_frame.style.horizontally_stretchable = true
      local subheader_frame = inside_frame.add{type = "frame", name = PANE_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.vertically_stretchable = true

    -- Add actual settings
    local settings_table = subheader_frame.add{type="table", column_count=2}
    settings_table.style.column_alignments[2] = "center"

    add_suggestions_settings(settings_table, player_table)
    add_undersupply_settings(settings_table, player_table)

    -- Exclusions frame
    local exclusions_frame = outer_flow.add{ type = "flow", name = PANE_NAME.."-exclusions", direction = "vertical" }
    exclusions_window.create_frame(exclusions_frame, player)
    player_table.ui.network_settings.exclusions_frame = exclusions_frame
    exclusions_window.show_exclusions(player_table, default_list_shown)
    exclusions_frame.visible = true
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
---@param use_default boolean True if resetting to default
---@param count? number The number of items in the list this setting refers to
local function update_list_setting(control, use_default, count)
  local changed = 0
  if use_default then
    count = control.default
  end
  if count > 0 then
    changed = 1
  end

  update_revert_button(control, changed > 0, {"network-settings.reset-list-setting"})
  if count > 0 then
    control.control.number = count
  else
    control.control.number = nil
  end
  control.control.enabled = count > 0

  return changed
end

---@param control NetworkSettingControls
---@param use_default boolean True if resetting to default
---@param state? boolean The new state, if not resetting it
---@return number Return number of settings changed (0 or 1)
function update_checkbox_setting(control, use_default, state)
  local changed = 0
  if use_default then
    state = control.default
  end
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

  -- Update network ID in title
  local header = player_table.ui.network_settings.network_id_header
  if header then
    if networkdata then
      header.caption = {"network-settings.window-title", network_id or 0}
    else
      header.caption = {"network-settings.no-network-title"}
    end
  end

  -- If there is no networkdata, show defaults
  local defaults = not networkdata
  -- Iterate over all settings and update them
  local num_changed = 0 -- Number of settings that are not the default
  for name, control in pairs(player_table.ui.network_settings) do
    if name == ignore_higher_quality_matches_setting then
      num_changed = num_changed + update_checkbox_setting(control, defaults, networkdata and networkdata.ignore_higher_quality_mismatches)
    elseif name == ignore_buffer_chests_setting then
      num_changed = num_changed + update_checkbox_setting(control, defaults, networkdata and networkdata.ignore_buffer_chests_for_undersupply)
    elseif name == ignore_low_storage_when_no_storage_setting then
      num_changed = num_changed + update_checkbox_setting(control, defaults, networkdata and networkdata.ignore_low_storage_when_no_storage)
    elseif name == mismatched_storage_setting then
      num_changed = num_changed + update_list_setting(control, defaults, networkdata and table_size(networkdata.ignored_storages_for_mismatch))
    elseif name == undersupply_ignore_list_setting then
      num_changed = num_changed + update_list_setting(control, defaults, networkdata and table_size(networkdata.ignored_items_for_undersupply))
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
  -- Finally, update the exclusions window if it's open
  exclusions_window.update(player_table)
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
  elseif name == ignore_low_storage_when_no_storage_setting then
    networkdata.ignore_low_storage_when_no_storage = new_value
  else
    return false
  end
end

-- Clear the relevant list and refresh the window to show the effect
local function clear_list_and_refresh(player_table, event)
  local network_id = player_table.settings_network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if event.element.tags.name == mismatched_storage_setting then
    -- Clear the list of ignored storages for mismatched storage suggestion
    network_data.clear_ignored_storages_for_mismatch(networkdata)
  elseif event.element.tags.name == undersupply_ignore_list_setting then
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
    networkdata.ignore_low_storage_when_no_storage = false
    networkdata.ignored_items_for_undersupply = {}
    network_data.clear_ignored_storages_for_mismatch(networkdata)
  end
end

--- Handle clicks
---@returns boolean true if the click was handled
function network_settings.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  -- First check for exclusion window clicks
  if exclusions_window.on_gui_click(event) then return end

  if not event.element.tags then return false end
  if not event.element.tags.pane or event.element.tags.pane ~= PANE_NAME then return false end

  local handled = false
  local action = event.element.tags.action
  local player_table = player_data.get_player_table(event.player_index)
  if player_table then
    local setting_name = event.element.tags.name
    local controls = player_table.ui.network_settings[setting_name]
    if controls then
      if controls.control and controls.control.valid then
        if controls.control.type == "checkbox" then
          set_checkbox_setting(player_table, setting_name, action, controls)
          handled = true
        end
        if action == "revert" then
          -- Revert button for a list setting
          if setting_name == mismatched_storage_setting or setting_name == undersupply_ignore_list_setting then
            clear_list_and_refresh(player_table, event)
            handled = true
          end
        end
        if action == "manage" then
          -- Change which exclusion list is shown
          exclusions_window.show_exclusions(player_table, setting_name)
          handled = true
        end
      end
    end

    if action == "revert-to-defaults" then
      revert_to_defaults(player_table, event)
      handled = true
    elseif action == "close" and player_table.ui.network_settings.settings_frame then
      local frame = player_table.ui.network_settings.settings_frame
      frame.visible = false
      events.emit(events.on_settings_pane_closed, event.player_index)
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