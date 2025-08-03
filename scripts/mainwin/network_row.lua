-- Network row functionality for the logistics insights GUI
-- Handles logistic network overview and status display

local network_row = {}

local player_data = require("scripts.player-data")
local tooltips_helper = require("scripts.tooltips-helper")

-- Cache frequently used functions
local pairs = pairs

--- Add the network row to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
function network_row.add(player_table, gui_table)
  player_data.register_ui(player_table, "network")
  local flow = gui_table.add {
    name = "bots_network_row",
    type = "flow",
    direction = "vertical"
  }
  flow.add {
    type = "label",
    caption = {"network-row.header"},
    style = "heading_2_label",
    tooltip = {"network-row.header-tooltip"},
  }
  player_table.ui.network.id = gui_table.add {
    type = "sprite-button",
    sprite = "virtual-signal/signal-L",
    style = "slot_button",
    name = "logistics-insights-network-id",
  }
  player_table.ui.network.roboports = gui_table.add {
    type = "sprite-button",
    sprite = "entity/roboport",
    style = "slot_button",
    name = "logistics-insights-roboports",
    tags = { follow = false }
  }
  player_table.ui.network.logistics_bots = gui_table.add {
    type = "sprite-button",
    sprite = "entity/logistic-robot",
    style = "slot_button",
    name = "logistics-insights-logistics_bots",
    tags = { follow = true }
  }
  player_table.ui.network.requesters = gui_table.add {
    type = "sprite-button",
    sprite = "item/requester-chest",
    style = "slot_button",
    name = "logistics-insights-requesters",
    tags = { follow = false }
  }
  player_table.ui.network.providers = gui_table.add {
    type = "sprite-button",
    sprite = "item/passive-provider-chest",
    style = "slot_button",
    name = "logistics-insights-providers",
    tags = { follow = false }
  }
  player_table.ui.network.storages = gui_table.add {
    type = "sprite-button",
    sprite = "item/storage-chest",
    style = "slot_button",
    name = "logistics-insights-storages",
    tags = { follow = false }
  }

  -- Pad with blank elements if needed
  local count = 6 -- No of network row items
  while count < player_table.settings.max_items do
    gui_table.add {
      type = "empty-widget",
    }
    count = count + 1
  end
end

--- Update the network information row with current statistics
--- @param player_table PlayerData The player's data table
function network_row.update(player_table)
  local function update_element(cell, value, localized_tooltip, clicktip)
    if cell and cell.valid then
      cell.number = value
      if localized_tooltip then
        if clicktip then
          cell.tooltip = {"", {localized_tooltip, value},  "\n", {clicktip}}
        else
          cell.tooltip = {localized_tooltip, value}
        end
      else
        cell.tooltip = ""
      end
    end
  end

  local function update_key_element(cell, value, main_completed_tooltip)
    if cell and cell.valid then
      cell.number = value
      cell.tooltip = {"", main_completed_tooltip}
    end
  end

  local function update_complex_element(cell, value, localized_tooltip, clicktip)
    if cell and cell.valid then
      cell.number = value
      if localized_tooltip then
        if clicktip then
          cell.tooltip = {"", localized_tooltip, "\n", {clicktip}}
        else
          cell.tooltip = {"", localized_tooltip, "\n"}
        end
      else
        cell.tooltip = ""
      end
    end
  end

  local reset_network_buttons = function(ui_table, sprite, number, tip, disable)
    -- Reset all cells in the ui_table to empty
    for _, cell in pairs(ui_table) do
      if cell and cell.type == "sprite-button" then
        if sprite then cell.sprite = "" end
        if tip then cell.tooltip = "" end
        if number then cell.number = nil end
        if disable then cell.enabled = false end
      end
    end
  end

  local function create_networkid_information_tooltip(network, network_id, is_fixed, clicktip)
    -- Line 1: Network ID: xyz (Dynamic/Fixed)
    local tip = {}
    tip = tooltips_helper.add_networkid_tip(tip, network_id, is_fixed)

    --- Located on: (Planet)
    tip = tooltips_helper.add_network_surface_tip(tip, network)

    -- History data: "Disabled in settings", "Paused", or "Collected for <time>"
    tip = tooltips_helper.add_network_history_tip(tip, player_table)

    return {"", tip, "\n\n", {clicktip}}
  end

  local function create_logistic_bots_tooltip(network)
    -- Line 1: Show no of bots
    local tip = { "", {"network-row.logistic-bots-tooltip", network.all_logistic_robots}, "\n" }

    -- Line 2: Show quality counts
    tip = tooltips_helper.get_quality_tooltip_line(tip, player_table, storage.total_bot_qualities, false)
    return tip
  end

  local networkidclicktip
  if player_table.fixed_network then
    networkidclicktip = "network-row.follow-network-tooltip"
  else
    networkidclicktip = "network-row.fixed-network-tooltip"
  end

  if player_table.network and player_table.network.valid and player_table.ui.network then
    -- Network ID cell and tooltip
    local network_id = player_table.network.network_id
    local networkidtip = create_networkid_information_tooltip(player_table.network, network_id, player_table.fixed_network, networkidclicktip)
    if player_table.ui.network.id then
      update_key_element(player_table.ui.network.id, network_id, networkidtip)
    end

    -- Roboports cell and tooltip
    if player_table.ui.network.roboports then
      update_complex_element(player_table.ui.network.roboports, table_size(player_table.network.cells),
        tooltips_helper.create_count_with_qualities_tip(player_table, "network-row.roboports-tooltip", table_size(player_table.network.cells), storage.roboport_qualities),
        "bots-gui.show-location-tooltip")
    end

    --  All Logistic Bots cell and tooltip
    local bottip
    if player_table.settings.pause_for_bots then
      bottip = "bots-gui.show-location-and-pause-tooltip"
    else
      bottip = "bots-gui.show-location-tooltip"
    end
    if player_table.ui.network.logistics_bots then
      update_complex_element(player_table.ui.network.logistics_bots, player_table.network.all_logistic_robots, create_logistic_bots_tooltip(player_table.network), bottip)
    end

    -- Requesters, Providers and Storages cells and tooltips
    if player_table.ui.network.requesters then
      update_element(player_table.ui.network.requesters, table_size(player_table.network.requesters), "network-row.requesters-tooltip", "bots-gui.show-location-tooltip")
    end
    if player_table.ui.network.providers then
      update_element(player_table.ui.network.providers, table_size(player_table.network.providers) - table_size(player_table.network.cells), "network-row.providers-tooltip", "bots-gui.show-location-tooltip")
    end
    if player_table.ui.network.storages then
      update_element(player_table.ui.network.storages, table_size(player_table.network.storages), "network-row.storages-tooltip", "bots-gui.show-location-tooltip")
    end
  else
    if player_table.ui.network then
      reset_network_buttons(player_table.ui.network, false, true, true, false)
    end
    if not player_table.fixed_network then
      networkidclicktip = "network-row.no-network-clicktip"
    end
    if player_table.ui.network and player_table.ui.network.id then
      update_element(player_table.ui.network.id, nil, "network-row.no-network-tooltip", networkidclicktip)
    end
  end
end -- update

return network_row