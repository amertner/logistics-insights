local events = {
  -- Triggered when the settings pane closes
  on_settings_pane_closed = script.generate_event_name(),
}

---@param event LuaEventType the name of the event that will be emited
---@param player_index number the player index that is associated with the event
function events.emit(event, player_index)
    script.raise_event(event, {
        name = event,
        tick = game.tick,
        player_index=player_index
    })
end

return events