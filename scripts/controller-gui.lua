local controller_gui = {}

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
  }
end

-- Update the mini window's counter
function controller_gui.update_window(player, bot_count)
  local gui = player.gui.top.logistics_insights_mini
  if not gui then
    controller_gui.create_window(player)
    gui = player.gui.top.logistics_insights_mini
  end

  if gui.logistics_insights_toggle_main then
    gui.logistics_insights_toggle_main.number = bot_count
  end
end

function controller_gui.onclick(event)
  if event.element.name == "logistics_insights_toggle_main" then
    local player = game.get_player(event.player_index)
    if not player or not player.valid then return end

    bots_gui.toggle_window_visible(player)
  end
end

return controller_gui
