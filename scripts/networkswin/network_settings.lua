--- Settings for a single network

local network_settings = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"

local WINDOW_NAME = "li_network_settings_window"
local WINDOW_MIN_HEIGHT = 110-3*24 -- Room for 0 networks
local WINDOW_MAX_HEIGHT = 110+10*24 -- Room for 12 networks
local clear_mismatched_storage_action="clear-mismatch-storage-list"
local clear_undersupply_ignore_list_action="clear-undersupply-ignore-list"

---@returns LuaGuiElement|nil
local function add_settings_header(ui, caption)
  if not ui or not ui.valid then return nil end

  local header = ui.add{type="label", caption=caption, style="caption_label"}
  return header
end

local function add_checkbox_setting(ui, setting_name, default_state)
  if not ui or not ui.valid or not setting_name then return end

  local checkbox = ui.add{type="checkbox", name="li_"..setting_name, 
    caption={"network-settings."..setting_name}, tooltip={"network-settings."..setting_name.."-tooltip"}, state=default_state}
  return checkbox
end

---@param ui LuaGuiElement The parent UI element to add the setting to
---@param nwid string The network ID to associate with the setting
---@param caption LocalisedString The caption for the setting
---@param action string The action tag to associate with the Clear button
---@param count number The number of items in the list (to enable/disable the Clear button
-- Add a setting that has a descriptive name and a Clear button
local function add_setting_with_clear_button(ui, nwid, caption, action, count)
  if not ui or not ui.valid or not caption then return end

  local setting_flow = ui.add{type="flow", direction="horizontal"}
  setting_flow.style.horizontal_spacing = 8
  local label = setting_flow.add{type="label", style="label", caption=caption}
  label.style.top_margin = 4
  local space = setting_flow.add {type = "empty-widget", style = "draggable_space"}
  space.style.horizontally_stretchable = true
  local button = setting_flow.add{type="button", style="other_settings_gui_button", tags={action=action, network_id=nwid}, caption={"network-settings.clear-list-button"}}
  button.enabled = (count and count > 0) or false
  return setting_flow
end

---@returns LuaGuiElement|nil
local function add_suggestions_settings(ui, player_table, networkdata)
  if not ui or not ui.valid or not networkdata then return end

  local setting_flow = ui.add{type="flow", direction="horizontal"}
  local vflow = setting_flow.add {type = "flow", direction = "vertical"}

  add_settings_header(vflow, {"network-settings.mismatched-storage-header"})
  local checkbox = add_checkbox_setting(vflow, "ignore-higher-quality-mismatches", networkdata.ignore_higher_quality_mismatches)
  player_table.ui.network_settings.ignore_higher_quality_mismatches = checkbox
  local count = table_size(networkdata.ignored_storages_for_mismatch)
  add_setting_with_clear_button(vflow, networkdata.id, {"network-settings.chests-on-ignore-list", count }, clear_mismatched_storage_action, count)
end

---@returns LuaGuiElement|nil
local function add_undersupply_settings(ui, player_table, networkdata)
  if not ui or not ui.valid or not networkdata then return end

  local setting_flow = ui.add{type="flow", direction="horizontal", name="undersupply_h"}
  local vflow = setting_flow.add {type = "flow", direction = "vertical", name="undersupply_v"}

  add_settings_header(vflow, {"network-settings.undersupply-header"})
  local count = table_size(networkdata.ignored_items_for_undersupply)
  add_setting_with_clear_button(vflow, networkdata.id, {"network-settings.items-on-undersupply-ignore-list", count}, clear_undersupply_ignore_list_action, count)
end

---@param player? LuaPlayer
---@param networkdata? LINetworkData
function network_settings.create_window(player, networkdata)
  if not player or not player.valid or not networkdata then return end
  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end

  player_data.register_ui(player_table, "network_settings")

  -- Destroy existing instance first
  if player.gui.screen[WINDOW_NAME] then
    player.gui.screen[WINDOW_NAME].destroy()
  end

  -- The main Networks window
  local window = player.gui.screen.add {type = "frame", name = WINDOW_NAME, direction = "vertical", style = "li_window_style", dialog = true}
  --window.style.vertically_stretchable = true
  --window.style.minimal_height = 300

    -- Title bar with dragger
    local titlebar = window.add {type = "flow", style = "fs_flib_titlebar_flow", name = WINDOW_NAME .. "-titlebar", drag_target = window}
      local label = titlebar.add {type = "label", name = WINDOW_NAME .. "-caption", style = "frame_title", ignored_by_interaction = true,
        caption = {"network-settings.window-title", networkdata.id}}
      label.style.top_margin = -4
      titlebar.drag_target = window
      titlebar.add {type = "empty-widget", style = "fs_flib_titlebar_drag_handle", ignored_by_interaction = true }

    -- Content: Area to host settings for the network
    local inside_frame = window.add{type = "frame", name = WINDOW_NAME.."-inside", style = "inside_deep_frame", direction = "vertical"}
      inside_frame.style.vertically_stretchable = true
      inside_frame.style.horizontally_stretchable = true
      local subheader_frame = inside_frame.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "vertical"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.vertically_stretchable = true
    -- Add actual settings
    add_suggestions_settings(subheader_frame,player_table, networkdata)
    add_undersupply_settings(subheader_frame, player_table, networkdata)

    -- Footer: Back and Confirm buttons
    local dialog_buttons_bar = window.add{type="flow", style="dialog_buttons_horizontal_flow", name="network_settings_buttons", direction="horizontal"}
    dialog_buttons_bar.add{type="button", style="back_button", caption={"network-settings.back-button"}, tags={action="li_cancel_settings"}}
    dialog_buttons_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle", ignored_by_interaction=true}
    dialog_buttons_bar.add{type="button", style="confirm_button", caption={"network-settings.confirm-button"}, tags={action="li_confirm_settings", network_id=networkdata.id}}
    dialog_buttons_bar.drag_target = window

  window.location = { x = 600, y = 100 }
end

local function close_settings_page(player_index)
  local player = game.get_player(player_index)
  if not player or not player.valid then return end
  if player.gui.screen[WINDOW_NAME] then
    player.gui.screen[WINDOW_NAME].destroy()
  end
  local player_table = player_data.get_player_table(player_index)
  if player_table then
    player_data.register_ui(player_table, "network_settings")
  end
end

local function cancel_settings_page(player_index)
  close_settings_page(player_index)
end

local function confirm_settings_page(event)
  -- Grab the updated settings
  local network_id = event.element.tags.network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  local player_table = player_data.get_player_table(event.player_index)
  if player_table then
    networkdata.ignore_higher_quality_mismatches = player_table.ui.network_settings.ignore_higher_quality_mismatches.state
  end
  close_settings_page(event.player_index)
end

-- Clear the relevant list and refresh the window to show the effect
function clear_list_and_refresh(event)
  local network_id = event.element.tags.network_id
  local networkdata = network_data.get_networkdata_fromid(network_id)
  if not networkdata then return false end

  if event.element.tags.action == clear_mismatched_storage_action then
    -- Clear the list of ignored storages for mismatched storage suggestion
    networkdata.ignored_storages_for_mismatch = {}
  elseif event.element.tags.action == clear_undersupply_ignore_list_action then
    -- Clear the list of ignored storages for undersupply
    networkdata.ignored_items_for_undersupply = {}
  end

  local player = game.get_player(event.player_index)
  network_settings.create_window(player, networkdata) -- Refresh the window to update the button state
end

---@returns boolean true if the click was handled
function network_settings.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if not event.element.tags then return false end

  if event.element.tags.action == "li_cancel_settings" then
    cancel_settings_page(event.player_index)
  elseif event.element.tags.action == "li_confirm_settings" then
    confirm_settings_page(event)
  elseif event.element.tags.action == clear_mismatched_storage_action or event.element.tags.action == clear_undersupply_ignore_list_action then
    clear_list_and_refresh(event)
  else
    return false
  end
  return true
end


return network_settings