local controller_gui = {}

local player_data = require("scripts.player-data")
local tooltips_helper = require("scripts.tooltips-helper")
local bots_gui = require("scripts.bots-gui")

-- Make sure we have access to storage
_ENV.storage = _ENV.storage or {}

-- Show the mini window (call this on player join or GUI update)
function controller_gui.create_window(player)
  local gui = player.gui.top
  if gui.logistics_insights_mini then gui.logistics_insights_mini.destroy() end

  -- Check if the mini window should be shown based on the setting
  if not player.mod_settings["li-show-mini-window"].value then
    return
  end

  local mini = gui.add {
    type = "frame",
    name = "logistics_insights_mini",
    style = "botsgui_controller_style",
    direction = "horizontal"
  }
  mini.location = { x = 10, y = 40 }

  mini.add {
    type = "sprite-button",
    name = "logistics_insights_toggle_main",
    sprite = "item/logistic-robot",
    style = "slot_button",
    tooltip = { "controller-gui.main_tooltip_click" }
  }
end

local function get_status(paused, enabled)
  if not enabled then
    return { "controller-gui.disabled" }
  else
    if paused then
      return { "controller-gui.paused" }
    else
      return { "controller-gui.active" }
    end
  end
end

-- Update the mini window's counter
function controller_gui.update_window(player, player_table)
  -- If the mini window should not be shown, return early
  if not player.mod_settings["li-show-mini-window"].value then
    -- Make sure to destroy any existing mini window
    if player.gui.top.logistics_insights_mini then 
      player.gui.top.logistics_insights_mini.destroy() 
    end
    return
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

  if gui.logistics_insights_toggle_main then
    local tip = {}
    if player_table.network and player_table.network then
      idle_count = storage.bot_items["logistic-robot-available"]
      total_count = storage.bot_items["logistic-robot-total"]
      gui.logistics_insights_toggle_main.number = idle_count

      tip = tooltips_helper.add_networkid_tip(tip,  player_table.network.network_id, player_table.fixed_network)
      tip = tooltips_helper.add_network_surface_tip(tip, player_table.network)
      tip = tooltips_helper.add_bots_idle_and_total_tip(tip, player_table.network, idle_count, total_count)
      tip = tooltips_helper.add_empty_line(tip)

      local paused = player_data.is_paused(player_table)
      tip = { "", tip, { "controller-gui.main_tooltip_delivering", get_status(paused, player_table.settings.show_delivering) } }
      tip = tooltips_helper.add_network_history_tip(tip, player_table)
      tip = { "", tip, { "controller-gui.main_tooltip_activity", get_status(paused, player_table.settings.show_activity) } }
    else
      gui.logistics_insights_toggle_main.number = nil
      tip = { "controller-gui.no-network" }
    end

    gui.logistics_insights_toggle_main.tooltip = { "", tip, { "controller-gui.main_tooltip_click" } }
  end
end

function controller_gui.onclick(event)
  if event.element.name == "logistics_insights_toggle_main" then
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    if event.button == defines.mouse_button_type.left then
      bots_gui.toggle_window_visible(player)

      player_table = player_data.get_singleplayer_table()
      controller_gui.update_window(player, player_table)
    end
  end
end

return controller_gui
