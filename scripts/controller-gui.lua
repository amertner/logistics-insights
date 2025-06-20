local controller_gui = {}

local bots_gui = require("scripts.bots-gui")

-- Show the mini window (call this on player join or GUI update)
function controller_gui.create_window(player)
  local gui = player.gui.top
  if gui.bot_insights_mini then gui.bot_insights_mini.destroy() end

  local mini = gui.add{
      type = "frame",
      name = "bot_insights_mini",
      style = "botsgui_controller_style",
      direction = "horizontal"
  }
  mini.location = {x = 10, y = 40} -- fixed position, adjust as needed

  mini.add{
      type = "sprite-button",
      name = "bot_insights_toggle_main",
      sprite = "item/logistic-robot",
      style = "slot_button",
  }
end

-- Update the mini window's counter
 function controller_gui.update_window(player, bot_count)
    local gui = player.gui.top.bot_insights_mini
    if not gui then 
      controller_gui.create_window(player)
      gui = player.gui.top.bot_insights_mini
    end

    if gui.bot_insights_toggle_main then
      gui.bot_insights_toggle_main.number = bot_count
    end
end

-- On click, toggle the main window
script.on_event(defines.events.on_gui_click, function(event)
    if event.element.name == "bot_insights_toggle_main" then
        local player = game.get_player(event.player_index)
        if not player or not player.valid then return end
        local gui = player.gui.screen
        if gui.bots_insights_window and gui.bots_insights_window.visible then
            bots_gui.hide_main_window(player)
        else
--            local pos = storage.bot_insights_positions and storage.bot_insights_positions[player.index]
            bots_gui.show_main_window(player)
        end
    end
end)

return controller_gui