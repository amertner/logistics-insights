--- Settings for a single network

local network_settings = {}

local player_data = require "scripts.player-data"
local network_data = require "scripts.network-data"

local WINDOW_NAME = "li_network_settings_window"
local WINDOW_MIN_HEIGHT = 110-3*24 -- Room for 0 networks
local WINDOW_MAX_HEIGHT = 110+10*24 -- Room for 12 networks

local function add_settings(settings_flow, default_name, gui_index)
  if not settings_flow or not settings_flow.valid then return end

  -- Example setting: A checkbox to enable/disable something
  local checkbox = settings_flow.add{type="checkbox", name="li_example_checkbox_"..gui_index, caption={"network-settings.example-checkbox", default_name}, state=true}
  checkbox.style.top_margin = 8
  checkbox.style.left_margin = 8
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

    -- Title bar with dragger and close
    local titlebar = window.add {type = "flow", style = "fs_flib_titlebar_flow", name = WINDOW_NAME .. "-titlebar", drag_target = window}
      local label = titlebar.add {type = "label", name = WINDOW_NAME .. "-caption", style = "frame_title", ignored_by_interaction = true,
        caption = {"network-settings.window-title", networkdata.id}}
      label.style.top_margin = -4
      titlebar.drag_target = window

    -- Content: Area to host settings for the network
    local inside_frame = window.add{type = "frame", name = WINDOW_NAME.."-inside", style = "inside_shallow_frame", direction = "vertical"}
      local subheader_frame = inside_frame.add{type = "frame", name = WINDOW_NAME.."-subheader", style = "subheader_frame", direction = "horizontal"}
      subheader_frame.style.minimal_height = WINDOW_MIN_HEIGHT -- This dictates how much there is room for
      subheader_frame.style.maximal_height = WINDOW_MAX_HEIGHT -- This dictates how much there is room for

    -- Footer: Back and Confirm buttons
    local dialog_buttons_bar = window.add{type="flow", style="dialog_buttons_horizontal_flow", name="network_settings_buttons", direction="horizontal"}
    dialog_buttons_bar.add{type="button", style="back_button", caption={"network-settings.back-button"}, tags={action="li_cancel_settings"}}
    dialog_buttons_bar.add{type="empty-widget", style="flib_dialog_footer_drag_handle", ignored_by_interaction=true}
    dialog_buttons_bar.add{type="button", style="confirm_button", caption={"network-settings.confirm-button"}, tags={action="li_confirm_settings"}}
    dialog_buttons_bar.drag_target = window

  window.location = { x = 600, y = 100 }
end

-- Override `Escape` on the settings page
script.on_event("li_cancel_settings", function(event)
    -- if is_settings_page_visible(event.player_index) then
    --     cancel_settings_page(event.player_index)
    --     storage.players[event.player_index].one_time_prevent_close = true
    -- end
end)

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

local function confirm_settings_page(player_index)
  -- Grab the updated settings
  close_settings_page(player_index)
end

---@returns boolean true if the click was handled
function network_settings.on_gui_click(event)
  if not event.element or not event.element.valid then return false end
  if not event.element.tags then return false end

  if event.element.tags.action == "li_cancel_settings" then
    cancel_settings_page(event.player_index)
    return true
  elseif event.element.tags.action == "li_confirm_settings" then
    confirm_settings_page(event.player_index)
    return true
  end
  return false
end


return network_settings