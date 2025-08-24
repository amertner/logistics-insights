--- Defines the "controller GUI" in the top left corner of the screen
local controller_gui = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local tooltips_helper = require("scripts.tooltips-helper")
local main_window = require("scripts.mainwin.main_window")
local networks_window = require("scripts.networkswin.networks_window")
local capability_manager = require("scripts.capability-manager")

--- Show the mini window (call this on player join or GUI update)
--- @param player LuaPlayer The player to create the window for
function controller_gui.create_window(player)
  local gui = player.gui.top
  if gui.logistics_insights_mini then gui.logistics_insights_mini.destroy() end

  local mini = gui.add {
    type = "frame",
    name = "logistics_insights_mini",
    style = "botsgui_controller_style",
    direction = "horizontal"
  }
  mini.location = { x = 10, y = 40 }

  mini.add {
    type = "sprite-button",
    name = "logistics_insights_toggle_networks",
    sprite = "virtual-signal/signal-stack-size",
    style = "slot_button",
    tooltip = { "controller-gui.networks_tooltip_click" }
  }
  mini.add {
    type = "sprite-button",
    name = "logistics_insights_toggle_main",
    sprite = "item/logistic-robot",
    style = "slot_button",
    tooltip = { "controller-gui.main_tooltip_click" }
  }
end

-- Build a status string with reason details based on capability UI state
-- Returns a LocalisedString like: "Paused — Paused by you" or "Active" or "Disabled in settings"
--- @param player_table PlayerData The player's data table
--- @param capability string The capability to check (e.g., "delivery", "activity")
--- @param enabled_setting boolean Whether the capability is enabled in settings
---@return LocalisedString
local function get_status_with_reason(player_table, capability, enabled_setting)
  local ui = capability_manager.get_ui_state(player_table, capability)
  -- If disabled in settings, show disabled regardless of other reasons
  if not enabled_setting or ui.state == "setting-paused" then
    return { "controller-gui.disabled" }
  end
  if ui.active then
    return { "controller-gui.active" }
  end
  -- Map derived state to a reason string
  local reason_key
  if ui.state == "user-paused" then
    reason_key = "controller-gui.reason-user"
  elseif ui.state == "hidden-paused" then
    reason_key = "controller-gui.reason-hidden"
  elseif ui.state == "no_network-paused" then
    reason_key = "controller-gui.reason-no-network"
  elseif ui.state == "dep-paused" then
    reason_key = "controller-gui.reason-dep"
  else
    reason_key = "controller-gui.reason-other"
  end
  return { reason_key }
end

---@param gui LuaGuiElement The GUI element to update
---@param player_table PlayerData The player's data table containing network and settings
local function update_main_tooltip(gui, player_table)
  local networkdata = network_data.get_networkdata(player_table.network)
  local tip = {}
  if player_table.network and player_table.network.valid and networkdata then
    local idle_count = networkdata.bot_items and networkdata.bot_items["logistic-robot-available"] or 0
    local total_count = networkdata.bot_items and networkdata.bot_items["logistic-robot-total"] or 0
    gui.logistics_insights_toggle_main.number = idle_count

    tip = tooltips_helper.add_networkid_tip(tip,  player_table.network.network_id, player_table.fixed_network)
    tip = tooltips_helper.add_network_surface_tip(tip, player_table.network)
    tip = tooltips_helper.add_bots_idle_and_total_tip(tip, player_table.network, idle_count, total_count)
    tip = tooltips_helper.get_quality_tooltip_line(tip, player_table, networkdata.total_bot_qualities, false, "controller-gui.main_tooltip_quality")
    tip = tooltips_helper.add_empty_line(tip)

    tip = { "", tip, { "controller-gui.main_tooltip_delivering", get_status_with_reason(player_table, "delivery", player_table.settings.show_delivering) } }
    tip = { "", tip, { "controller-gui.main_tooltip_history", get_status_with_reason(player_table, "history", player_table.settings.show_history) } }
    tip = { "", tip, { "controller-gui.main_tooltip_activity", get_status_with_reason(player_table, "activity", player_table.settings.show_activity) } }
    tip = { "", tip, { "controller-gui.main_tooltip_undersupply", get_status_with_reason(player_table, "undersupply", player_table.settings.show_undersupply) } }
    tip = { "", tip, { "controller-gui.main_tooltip_suggestions", get_status_with_reason(player_table, "suggestions", player_table.settings.show_suggestions) } }
  else
    gui.logistics_insights_toggle_main.number = nil
    tip = { "controller-gui.no-network" }
  end

  gui.logistics_insights_toggle_main.tooltip = { "", tip, { "controller-gui.main_tooltip_click" } }
end

---@param gui LuaGuiElement The GUI element to update
---@param player_table PlayerData The player's data table containing network and settings
local function update_networks_tooltip(gui, player_table)
  -- #TODO: Show count of networks being scanned, not all networks
  local networkcount = table_size(storage.networks)
  gui.logistics_insights_toggle_networks.number = networkcount

  local tip
  tip = { "", tip, { "controller-gui.network_count", networkcount } }
  tip = { "", tip, { "controller-gui.networks_tooltip_click" } }

  gui.logistics_insights_toggle_networks.tooltip = tip
end

--- Update the mini window's counter and tooltip
--- @param player? LuaPlayer The player whose window to update
--- @param player_table? PlayerData The player's data table containing network and settings
function controller_gui.update_window(player, player_table)
  if not player then
    return -- No player, nothing to update
  end

  local gui = player.gui.top.logistics_insights_mini
  if not gui then
    controller_gui.create_window(player)
    gui = player.gui.top.logistics_insights_mini
  end

  -- If gui is still nil after trying to create it, return early
  if not gui then
    return
  end

  if player_table then
    update_networks_tooltip(gui, player_table)
  end
  if gui.logistics_insights_toggle_main and player_table then
    update_main_tooltip(gui, player_table)
  end
end

--- Handle click events on the controller GUI elements
--- @param event EventData.on_gui_click The click event data containing element and player information
function controller_gui.onclick(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end

  if event.element.name == "logistics_insights_toggle_main" then
    if event.button == defines.mouse_button_type.left then
      main_window.toggle_window_visible(player)

      local player_table = player_data.get_player_table(event.player_index)
      controller_gui.update_window(player, player_table)
    end
  elseif event.element.name == "logistics_insights_toggle_networks" then
    if event.button == defines.mouse_button_type.left then
      networks_window.toggle_window_visible(player)
    end
  end
end

return controller_gui
