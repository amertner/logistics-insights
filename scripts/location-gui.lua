-- Code to handle a GUI that shows the locations of entities
local locations_window = {}

local player_data = require("scripts.player-data")

function locations_window.create(player, player_table)
    -- Check if the window already exists
    if player.gui.screen.locations_window then
        return
    end

    -- Create the window
    local window = player.gui.screen.add{
        type = "frame",
        name = "locations_window",
        caption = "Locations",
        direction = "vertical"
    }

    -- Restore the window's location if it was previously saved
    if player_table.locations_window_location then
        window.location = player_table.locations_window_location
    end
    
    -- Add a titlebar flow for the "X" button
    local titlebar = window.add{
        type = "flow",
        name = "locations_titlebar",
        direction = "horizontal"
    }
    titlebar.drag_target = window  -- Make the titlebar draggable

    -- Add the "X" button to the titlebar
    local close_button = titlebar.add{
        type = "sprite-button",
        name = "locations_close_button",
        sprite = "utility/close_white",
        style = "frame_action_button",
        tooltip = "Close"
    }

    -- Add content below the titlebar
    local content = window.add{
        type = "flow",
        name = "locations_content",
        direction = "vertical"
    }

    -- Make the window draggable
    window.style.size = {300, 200}  -- Set a default size
    window.style.padding = 10
end

function locations_window.destroy(player, player_table)
    local window = player.gui.screen.locations_window
    if window then
        -- Save the window's location before destroying it
        player_table.locations_window_location = window.location
        window.destroy()
    end
end

function locations_window.handle_gui_click(event)
    local player = game.get_player(event.player_index)
    local player_table = player_data.get_singleplayer_table()

    if event.element.name == "locations_close_button" then
        locations_window.destroy(player, player_table)
    end
end

function locations_window.on_init()
    local player = player_data.get_singleplayer_player()
    local player_table = player_data.get_singleplayer_table()
    locations_window.create(player, player_table)
end

-- Register events
script.on_event(defines.events.on_gui_click, locations_window.handle_gui_click)
script.on_init(locations_window.on_init)

return locations_window