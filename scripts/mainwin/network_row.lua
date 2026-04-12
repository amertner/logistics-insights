-- Network row functionality for the logistics insights GUI
-- Handles logistic network overview and status display

local network_row = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local global_data = require("scripts.global-data")
local tooltips_helper = require("scripts.tooltips-helper")
local mini_button = require("scripts.mainwin.mini_button")
local tools = require("scripts.utils")

-- Cache frequently used functions
local pairs = pairs
local debugger = require("scripts.debugger")
local PROFILING = debugger.PROFILING

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
  local hcell = flow.add {
    type = "flow",
    direction = "horizontal"
  }
  hcell.add {
    type = "label",
    caption = {"network-row.header"},
    style = "heading_2_label",
    tooltip = {"network-row.header-tooltip"},
  }
  hcell.style.horizontally_stretchable = true
  player_table.ui.network.settings_button = mini_button.add(player_table, hcell, "network", {"network-row.networks-tooltip"}, "settings", false)

  local spr_log_system = tools.get_valid_sprite_path("technology/", "logistic-system", "virtual-signal/signal-N")
  player_table.ui.network.id = gui_table.add {
    type = "sprite-button",
    sprite = spr_log_system,
    style = "slot_button",
    name = "logistics-insights-network-id",
  }
  player_table.ui.network.roboports = gui_table.add {
    type = "sprite-button",
    sprite = "item/roboport",
    style = "slot_button",
    name = "logistics-insights-roboports",
    raise_hover_events = true,
    tags = { follow = false }
  }
  player_table.ui.network.logistics_bots = gui_table.add {
    type = "sprite-button",
    sprite = "item/logistic-robot",
    style = "slot_button",
    name = "logistics-insights-logistics_bots",
    raise_hover_events = true,
    tags = { follow = true }
  }
  player_table.ui.network.requesters = gui_table.add {
    type = "sprite-button",
    sprite = "item/requester-chest",
    style = "slot_button",
    name = "logistics-insights-requesters",
    raise_hover_events = true,
    tags = { follow = false }
  }
  player_table.ui.network.providers = gui_table.add {
    type = "sprite-button",
    sprite = "item/passive-provider-chest",
    style = "slot_button",
    name = "logistics-insights-providers",
    raise_hover_events = true,
    tags = { follow = false }
  }
  player_table.ui.network.storages = gui_table.add {
    type = "sprite-button",
    sprite = "item/storage-chest",
    style = "slot_button",
    name = "logistics-insights-storages",
    raise_hover_events = true,
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
  return 1
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

  ---@param player_table PlayerData
  ---@param networkdata LINetworkData
  ---@param is_fixed boolean
  ---@param clicktip string
  ---@return table<LocalisedString>
  local function create_networkid_information_tooltip(player_table, networkdata, is_fixed, clicktip)
    -- Line 1: Network ID: xyz (Dynamic/Fixed)
    local tip = {}
    tip = tooltips_helper.add_networkid_tip(tip, networkdata.id, is_fixed)

    --- Located on: (Planet)
    tip = tooltips_helper.add_network_surface_tip(tip, networkdata.surface)

    -- History data: "Disabled in settings", "Paused", or "Collected for <time>"
    tip = tooltips_helper.add_network_history_tip(tip, player_table, networkdata)

    return {"", tip, "\n\n", {clicktip}}
  end

  local function create_logistic_bots_tooltip(network, networkdata, include_quality)
    -- Line 1: Show no of bots
    local tip = { "", {"network-row.logistic-bots-tooltip", network.all_logistic_robots}, "\n" }

    -- Line 2: Show quality counts
    if include_quality then
      tip = tooltips_helper.get_quality_tooltip_line(tip, networkdata.total_bot_qualities, false)
    end
    return tip
  end

  local networkidclicktip
  if player_table.fixed_network then
    networkidclicktip = "network-row.follow-network-tooltip"
  else
    networkidclicktip = "network-row.fixed-network-tooltip"
  end

  local networkdata = network_data.get_networkdata(player_table.network)
  if player_table.network and player_table.network.valid and player_table.ui.network and networkdata then
    local p
    -- Network ID cell and tooltip
    if PROFILING then p = helpers.create_profiler() end
    local network_id = player_table.network.network_id
    local networkidtip = create_networkid_information_tooltip(player_table, networkdata, player_table.fixed_network, networkidclicktip)
    if player_table.ui.network.id then
      update_key_element(player_table.ui.network.id, network_id, networkidtip)
    end
    if PROFILING then p.stop() log({"", "[perf] netrow: id=", p}) end

    -- Roboports cell and tooltip
    if PROFILING then p = helpers.create_profiler() end
    player_table.ui.network.roboports.enabled = true
    update_complex_element(player_table.ui.network.roboports, networkdata.total_cells,
      tooltips_helper.create_count_with_qualities_tip("network-row.roboports-tooltip", networkdata.total_cells, networkdata.roboport_qualities),
      "bots-gui.show-location-tooltip")
    if PROFILING then p.stop() log({"", "[perf] netrow: roboports=", p}) end

    --  All Logistic Bots cell and tooltip
    if PROFILING then p = helpers.create_profiler() end
    local bottip
    if global_data.freeze_highlighting_bots() then
      bottip = "bots-gui.show-location-and-pause-tooltip"
    else
      bottip = "bots-gui.show-location-tooltip"
    end
    update_complex_element(player_table.ui.network.logistics_bots, player_table.network.all_logistic_robots,
      create_logistic_bots_tooltip(player_table.network, networkdata, true), bottip)
    if PROFILING then p.stop() log({"", "[perf] netrow: bots=", p}) end

    -- Requesters, Providers and Storages cells and tooltips
    if PROFILING then p = helpers.create_profiler() end
    update_element(player_table.ui.network.requesters, networkdata.requester_count or 0, "network-row.requesters-tooltip", "bots-gui.show-location-tooltip")
    if PROFILING then p.stop() log({"", "[perf] netrow: requesters=", p}) end

    if PROFILING then p = helpers.create_profiler() end
    player_table.ui.network.providers.enabled = true
    -- Count how many providers are not roboports
    local providers_count = math.max(0, (networkdata.provider_count or 0) - (networkdata.total_cells or 0))
    update_element(player_table.ui.network.providers, providers_count, "network-row.providers-tooltip", "bots-gui.show-location-tooltip")
    if PROFILING then p.stop() log({"", "[perf] netrow: providers=", p}) end

    if PROFILING then p = helpers.create_profiler() end
    update_element(player_table.ui.network.storages, networkdata.storage_count or 0, "network-row.storages-tooltip", "bots-gui.show-location-tooltip")
    if PROFILING then p.stop() log({"", "[perf] netrow: storages=", p}) end
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