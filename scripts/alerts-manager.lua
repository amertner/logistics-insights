--- Manage alerts initiated by Logistics Insights
local alerts_manager = {}

local player_data = require("scripts.player-data")
local network_data = require("scripts.network-data")
local capability_manager = require("scripts.capability-manager")
local suggestions = require("scripts.suggestions")
local utils = require("scripts.utils")

-- Display alerts to the player about important events
function alerts_manager.show_alerts(player, player_table)
  if not player or not player.valid or not player_table then
    return
  end
  show_suggestions = capability_manager.is_active(player_table, "suggestions")
  if not show_suggestions then
    alerts_manager.clear_suggestions_alert(player)
    return
  end

  if storage.networks then
    -- Find all suggestions and add them as alerts
    for _, networkdata in pairs(storage.networks) do
      if networkdata and networkdata.suggestions then
        alerts_manager.add_alerts_for_network(player, player_table, networkdata)
      end
    end
  end
end

--- @param player LuaPlayer The player to add alerts for
--- @param player_table PlayerData The player's data table containing network and settings
--- @param networkdata LINetworkData The network data to add alerts from
function alerts_manager.add_alerts_for_network(player, player_table, networkdata)
  local suggestions_table = networkdata.suggestions

  local order = (suggestions_table and suggestions_table.order) or (suggestions_table.order) or {}
  local suggestions_list = suggestions_table:get_suggestions()
  for _, key in ipairs(order) do
    local s = suggestions_list[key]
    if s then
      local network = network_data.get_LuaNetwork(networkdata)
      if network then
        local entity = nil
        local icon = {type="item", name="roboport"}
        if s.name == "waiting-to-charge" or s.name == "too-many-bots" or s.name == "too-few-bots" then
          icon = {type="item", name="logistic-robot"}
          local cell = network.cells[1] -- utils.get_random(network.cells)
          if cell and cell.valid and cell.owner and cell.owner.valid then
            entity = cell.owner
          end
          if entity and entity.valid then
            player.add_custom_alert(entity, icon, "Bots issue", false)
          end

        elseif s.name == "mismatched-storage" then
          icon = {type="item", name="storage-chest"}
          local list = networkdata.suggestions:get_cached_list(s.name)
          for _, chest in pairs(list or {}) do
            if chest and chest.valid then
              player.add_custom_alert(chest, icon, "Mismatched storage", true)
            end
          end
        end
      end
    end
  end
end


function alerts_manager.clear_suggestions_alert(player)
  if not player or not player.valid then
    return
  end
  -- Not really necessary as Factorio clears custom alerts that are not re-added after a minute or so
end

return alerts_manager
