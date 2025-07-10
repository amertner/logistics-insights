local controller_gui = {}

local player_data = require("scripts.player-data")
local bots_gui = require("scripts.bots-gui")

-- Show the mini window (call this on player join or GUI update)
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
    name = "logistics_insights_toggle_main",
    sprite = "item/logistic-robot",
    style = "slot_button",
    tooltip = {"controller-gui.main_tooltip_click"},
  }
end

local function get_status(paused)
  if paused then
    return {"controller-gui.paused"}
  else
    return {"controller-gui.active"}
  end
end

-- Update the mini window's counter
function controller_gui.update_window(player, player_table)
  local gui = player.gui.top.logistics_insights_mini
  if not gui then
    controller_gui.create_window(player)
    gui = player.gui.top.logistics_insights_mini
  end

  if gui.logistics_insights_toggle_main then
    idle_count = storage.bot_items["logistic-robot-available"]
    total_count = storage.bot_items["logistic-robot-total"]
    gui.logistics_insights_toggle_main.number = idle_count
    tip = {"controller-gui.main_tooltip", idle_count, total_count, player_table.network.network_id}
    if player_table.settings.show_delivering then
      status = get_status(player_data.is_paused(player_table))
      tip = {"", tip, {"controller-gui.main_tooltip_delivering", status}}
    end
    if player_table.settings.show_history then
      status = get_status(player_data.is_paused(player_table))
      tip = {"", tip, {"controller-gui.main_tooltip_history", status}}
    end
    if player_table.settings.show_activity then
      if player_data.is_paused(player_table) then
        if player_table.settings.show_delivering or player_table.settings.show_history then
          status = {"controller-gui.partial"}
        else
          status = {"controller-gui.active"}
        end
      else
        status = {"controller-gui.active"}
      end
      tip = {"", tip, {"controller-gui.main_tooltip_activity", status}}
    end

    gui.logistics_insights_toggle_main.tooltip = {"", tip, {"controller-gui.main_tooltip_click"}}
  end
end

function controller_gui.onclick(event)
  if event.element.name == "logistics_insights_toggle_main" then
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    bots_gui.toggle_window_visible(player)

    player_table = player_data.get_singleplayer_table()
    controller_gui.update_window(player, player_table)
  end
end

return controller_gui
