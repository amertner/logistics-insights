local bots_gui = {}

-- Hide the main window and save its position
function bots_gui.hide_main_window(player, player_table)
    local gui = player.gui.screen
    if gui.bots_insights_window then
        -- Save position
--        player_table.bot_insights_positions = player_table.bot_insights_positions or {}
        --player_table.bot_insights_positions[player.index] = gui.bots_insights_window.location
        gui.bots_insights_window.visible = false
    end
end

function bots_gui.show_main_window(player, player_table)
    local gui = player.gui.screen
    if gui.bots_insights_window then
        gui.bots_insights_window.visible = true
    end
end

function bots_gui.build(player, player_table)
  if player.gui.screen.bots_insights_window then
    player.gui.screen.bots_insights_window.destroy()
  end

  local style = "botsgui_frame_style"

  local window = player.gui.screen.add{
      type = "frame",
      name = "bots_insights_window",
      caption = "Bots",
      direction = "vertical",
      style = style,
      visible = player.controller_type ~= defines.controllers.cutscene,
  }
  player_table.bots_windows = window
  window.auto_center = true

  local bots_table = window.add{
    type = "table",
    name = "test_table",
    column_count = player_table.settings.max_items+1
  }
  player_table.bots_table =bots_table

  bots_gui.update(player, player_table)
end

-- Replace any character not allowed with an underscore
local function sanitize_entity_name(str)
    -- Convert to lowercase, replace invalid chars with "_"
    return string.gsub(string.lower(str), "[^a-z0-9_-]", "_")
end

-- Adds table GUI element displaying item sprites and numbers in sort order.
function add_sorted_item_table(title, gui_table, all_entries, sort_fn, number_field, max_items)
    -- Collect entries into an array
    local sorted_entries = {}

    for index, entry in pairs(all_entries) do
      if number_field then
        table.insert(sorted_entries, entry)
      else
        table.insert(sorted_entries, {
            item_name = index,
            count = entry or 0
        })
      end
    end
    if number_field == nil then
      number_field = "count" -- Default field if not specified
    end

    -- Sort using the provided function
    table.sort(sorted_entries, sort_fn)

    gui_table.add{
      type = "label",
      caption = title,
      style = "heading_2_label"
    }

    -- Add up to max_items entries
    local count = 0
    for _, entry in ipairs(sorted_entries) do
        if count >= max_items then break end
        gui_table.add{
            type = "sprite-button",
            sprite = "item/" .. entry.item_name,
            style = "slot_button",
            quality = entry.quality_name or "normal",
            number = entry[number_field],
            name = "bot-insight-test-"..sanitize_entity_name(title)..count
        }
        count = count + 1
    end

    -- Pad with blank elements if needed
    while count < max_items do
        gui_table.add{
            type = "sprite-button",
            style = "slot_button",
            name = "bot-insight-test-"..sanitize_entity_name(title)..count
        }
        count = count + 1
    end

    return gui_table
end

function bots_gui.update(player, player_table)
  local window = player.gui.screen.bots_insights_window
  if not window then
    -- bots_gui.build(player, player_table)
    return
  end

  local bots_table = player_table.bots_table
  if not bots_table or not bots_table.valid then
    return
  end

  bots_table.clear()

  if player_table.settings.show_delivering then
    add_sorted_item_table(
      "Deliveries",
      bots_table,
      storage.bot_deliveries,
      function(a, b) return a.count > b.count end,
      "count",
      player_table.settings.max_items
    )
  end

  -- Show history data
  if player_table.settings.show_history and storage.delivery_history then
    add_sorted_item_table(
        "Total items",
        bots_table,
        storage.delivery_history,
        function(a, b) return a.count > b.count end,
        "count",
        player_table.settings.max_items
    )
    add_sorted_item_table(
        "Total ticks",
        bots_table,
        storage.delivery_history,
        function(a, b) return a.ticks > b.ticks end,
        "ticks",
        player_table.settings.max_items
    )
    add_sorted_item_table(
        "Ticks/item",
        bots_table,
        storage.delivery_history,
        function(a, b) return a.avg > b.avg end,
        "avg",
        player_table.settings.max_items
    )

    -- Add button to clear history
    bots_table.add{
      type = "sprite-button",
      sprite = "utility/trash",
      style = "tool_button",
      tooltip = "Clear history",
      name = "bot-insight-test-clear-history"
    }
  end

  local in_train_gui = player.opened_gui_type == defines.gui_type.entity and player.opened.type == "locomotive"
  window.visible = not in_train_gui
end

script.on_event(defines.events.on_gui_click, function(event)
    if string.sub(event.element.name, 1, 16) == "bot-insight-test" then
        -- Do nothing, or show a message, etc.
    end
    if event.element.name == "bot-insight-test-clear-history" then
        storage.delivery_history = {}
        for _, player in pairs(game.connected_players) do
            local player_table = storage.players[player.index]
            bots_gui.update(player, player_table)
        end
      elseif event.element.name == "bot_insights_toggle_main" then
        local player = game.get_player(event.player_index)
        if not player or not player.valid then return end
        local gui = player.gui.screen
        if gui.bot_insights_main then
            bots_gui.hide_main_window(player)
        else
            local pos = storage.bot_insights_positions and storage.bot_insights_positions[player.index]
            bots_gui.show_main_window(player, pos)
        end
    end
end)

function bots_gui.destroy(player_table)
  local bots_windows = player_table.bots_windows
  if bots_windows and bots_windows.valid then
    bots_windows.destroy()
    player_table.bots_windows = nil
  end
end

return bots_gui
