--- Defines the "controller GUI" in the top left corner of the screen
local controller_gui = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local tooltips_helper = require("scripts.tooltips-helper")
local main_window = require("scripts.mainwin.main_window")
local networks_window = require("scripts.networkswin.networks_window")

--- Show the mini window (call this on player join or GUI update)
--- @param player LuaPlayer The player to create the window for
function controller_gui.create_window(player)
  local gui = player.gui.top
  if gui.logistics_insights_mini then gui.logistics_insights_mini.destroy() end

  local player_table = player_data.get_player_table(player.index)
  if not player_table then return end
  if not player_table.settings then return end
  if not (player_table.settings.show_networks_mini_window or player_table.settings.show_main_mini_window) then
    return -- Both mini windows are disabled in settings
  end

  local mini = gui.add {
    type = "frame",
    name = "logistics_insights_mini",
    style = "botsgui_controller_style",
    direction = "horizontal"
  }
  mini.location = { x = 10, y = 40 }

  if player_table.settings.show_networks_mini_window then
    mini.add {
      type = "sprite-button",
      name = "logistics_insights_toggle_networks",
      sprite = "li_suggestions_centered",
      style = "slot_button",
      tooltip = { "controller-gui.networks_tooltip_click" }
    }
  end
  if player_table.settings.show_main_mini_window then
    mini.add {
      type = "sprite-button",
      name = "logistics_insights_toggle_main",
      sprite = "item/logistic-robot",
      style = "slot_button",
      tooltip = { "controller-gui.main_tooltip_click" }
    }
  end
end

---@param gui LuaGuiElement The GUI element to update
---@param player_table PlayerData The player's data table containing network and settings
local function update_main_tooltip(gui, player_table)
  local networkdata = network_data.get_networkdata(player_table.network)
  local tip = {}
  if player_table.network and player_table.network.valid and networkdata and player_table.settings.show_main_mini_window and gui.logistics_insights_toggle_main then
    local idle_count = networkdata.bot_items and networkdata.bot_items["logistic-robot-available"] or 0
    local total_count = networkdata.bot_items and networkdata.bot_items["logistic-robot-total"] or 0
    gui.logistics_insights_toggle_main.number = idle_count

    tip = tooltips_helper.add_networkid_tip(tip,  player_table.network.network_id, player_table.fixed_network)
    tip = tooltips_helper.add_network_surface_tip(tip, player_table.network)
    tip = tooltips_helper.add_bots_idle_and_total_tip(tip, idle_count, total_count)
    tip = tooltips_helper.get_quality_tooltip_line(tip, networkdata.total_bot_qualities, false, "controller-gui.main_tooltip_quality")
  else
    if gui.logistics_insights_toggle_main then
      gui.logistics_insights_toggle_main.number = nil
    end
    tip = { "controller-gui.no-network" }
  end

  if gui.logistics_insights_toggle_main then
    gui.logistics_insights_toggle_main.tooltip = { "", tip, { "controller-gui.main_tooltip_click" } }
  end
end

---@param gui LuaGuiElement The GUI element to update
---@param player_table PlayerData The player's data table containing network and settings
local function update_networks_tooltip(gui, player_table)
  -- Get the number of suggestions across all networks
  if player_table.settings.show_networks_mini_window and gui.logistics_insights_toggle_networks then
    local total_counts = network_data.get_total_suggestions_and_undersupply()
    gui.logistics_insights_toggle_networks.number = total_counts.suggestions

    local networkcount = table_size(storage.networks)
    local tip
    tip = { "", tip, { "controller-gui.networks_1suggestions_2_undersupplies_3networks", total_counts.suggestions, total_counts.undersupplies, networkcount } }
    if global_data.background_scans_disabled() then
      tip = { "", tip, "\n", { "controller-gui.background_scanning_paused" } }
    end
    tip = { "", tip, { "controller-gui.networks_tooltip_click" } }

    gui.logistics_insights_toggle_networks.tooltip = tip
  end
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
--- @return boolean True if the event was handled, false otherwise
function controller_gui.onclick(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return false end

  local handled = false
  if event.element.name == "logistics_insights_toggle_main" then
    if event.button == defines.mouse_button_type.left then
      main_window.toggle_window_visible(player)

      local player_table = player_data.get_player_table(event.player_index)
      controller_gui.update_window(player, player_table)
      handled = true
    end
  elseif event.element.name == "logistics_insights_toggle_networks" then
    if event.button == defines.mouse_button_type.left then
      networks_window.toggle_window_visible(player)
      handled = true
    end
  end
  return handled
end

return controller_gui
