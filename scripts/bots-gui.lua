local bots_gui = {}

function bots_gui.toggle_window_visible(player)
  if not player then
    return
  end
  local player_table = storage.players[player.index]
  player_table.bots_window_visible = not player_table.bots_window_visible

  local gui = player.gui.screen
  if gui.bots_insights_window then
      gui.bots_insights_window.visible = player_table.bots_window_visible
  end
end

function bots_gui.create_window(player, player_table)
  if player.gui.screen.bots_insights_window then
    player.gui.screen.bots_insights_window.destroy()
  end

  local style = "botsgui_frame_style"

  local window = player.gui.screen.add{
      type = "frame",
      name = "bots_insights_window",
      caption = "[img=item/logistic-robot] Bots insights",
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
local function add_sorted_item_table(title, gui_table, all_entries, sort_fn, number_field, max_items)
    -- Collect entries into an array
    local sorted_entries = {}

    for index, entry in pairs(all_entries) do
      table.insert(sorted_entries, entry)
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
            name = "bot-insight-test-"..sanitize_entity_name(title)..count,
            tooltip = string.format("Items: %d", entry.count)
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
end

function bots_gui.update(player, player_table)
  if not player_table or player_table.bots_window_visible == false then
    return
  end

  window = player.gui.screen.bots_insights_window
  if not window then
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

    -- Show the bot network being inspected
    if player_table.network then
      bots_table.add{
        type = "sprite-button",
        sprite = "virtual-signal/signal-L",
        number = player_table.network.network_id,
        style = "slot_button",
        tooltip = "Network ID",
        name = "bot-insight-test-network-id",
        enabled = false
      }
      bots_table.add{
        type = "sprite-button",
        sprite = "entity/roboport",
        style = "slot_button",
        tooltip = "Number of roboports in network",
        number = table_size(player_table.network.cells),
        enabled = false,
      }
      bots_table.add{
        type = "sprite-button",
        sprite = "entity/logistic-robot",
        style = "slot_button",
        tooltip = "Number of logistics bots in network",
        number = player_table.network.all_logistic_robots,
        enabled = false,
      }
      bots_table.add{
        type = "sprite-button",
        sprite = "item/requester-chest",
        style = "slot_button",
        tooltip = "Number of requesters in network (Chests, Silos, etc)",
        number = table_size(player_table.network.requesters),
        enabled = false,
      }
      bots_table.add{
        type = "sprite-button",
        sprite = "item/passive-provider-chest",
        style = "slot_button",
        tooltip = "Number of providers in network, except roboports)",
        number = table_size(player_table.network.providers)-table_size(player_table.network.cells),
        enabled = false,
      }
      bots_table.add{
        type = "sprite-button",
        sprite = "item/storage-chest",
        style = "slot_button",
        tooltip = "Number of storage chests in network",
        number = table_size(player_table.network.storages),
        enabled = false,
      }
    else
      bots_table.add{
        type = "sprite-button",
        sprite = "virtual-signal/signal-L",
        style = "slot_button",
        tooltip = "No network in range",
        name = "bot-insight-test-network-id",
        enabled = false,
      }
    end
  end

  local in_train_gui = player.opened_gui_type == defines.gui_type.entity and player.opened.type == "locomotive"
  window.visible = not in_train_gui
end

function bots_gui.onclick(event)
    if string.sub(event.element.name, 1, 16) == "bot-insight-test" then
        -- Do nothing
    end
    if event.element.name == "bot-insight-test-clear-history" then
        storage.delivery_history = {}
        for _, player in pairs(game.connected_players) do
            local player_table = storage.players[player.index]
            bots_gui.update(player, player_table)
        end
    end
end

function bots_gui.destroy(player_table)
  local bots_windows = player_table.bots_windows
  if bots_windows and bots_windows.valid then
    bots_windows.destroy()
    player_table.bots_windows = nil
  end
end

return bots_gui
