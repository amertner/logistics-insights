
bot_counter = {}

local function add_bot_to_bot_deliveries(bot, item_name, quality, count)
    if storage.bot_deliveries[item_name .. quality] == nil then
        -- Order not seen before
        storage.bot_deliveries[item_name .. quality] = {
            item_name = item_name,
            quality_name = quality,
            count = count,
        }
    else -- It's still under way
        storage.bot_deliveries[item_name .. quality].count = storage.bot_deliveries[item_name .. quality].count + count
    end    
end

local function add_bot_to_active_deliveries(bot, item_name, quality, count)
    if storage.bot_active_deliveries[bot.unit_number] == nil then
        -- Order not seen before
        storage.bot_active_deliveries[bot.unit_number] = {
            item_name = item_name,
            quality_name = quality,
            count = count,
            first_seen = game.tick,
            last_seen = game.tick,
        }
    else -- It's still under way
        storage.bot_active_deliveries[bot.unit_number].last_seen = game.tick
    end
end

local function manage_active_deliveries_history()
    -- This function is called to manage the history of active deliveries
    -- It will remove entries that are no longer active and update the history
    for unit_number, order in pairs(storage.bot_active_deliveries) do
        if order.last_seen < game.tick then
            local key = order.item_name .. order.quality_name
            if storage.delivery_history[key] == nil then
                storage.delivery_history[key] = {
                    item_name = order.item_name,
                    quality_name = order.quality_name,
                    count = 0,
                    ticks = 0,
                }
            end
            local history_order = storage.delivery_history[key]
            history_order.count = (history_order.count or 0) + order.count
            local ticks = order.last_seen - order.first_seen
            if ticks < 1 then ticks = 1 end
            history_order.ticks = (history_order.ticks or 0) + ticks
            history_order.avg = history_order.ticks / history_order.count
            storage.bot_active_deliveries[unit_number] = nil -- remove from active list
        end
    end
end

function bot_counter.count_bots(game)
    storage.bot_items = {}
    storage.bot_deliveries = {}
    if storage.bot_active_deliveries == nil then
        storage.bot_active_deliveries = {}
    end
    local bots_total = 0
    local bots_available = 0
    local bots_charging = 0
    local bots_waiting_for_charge = 0
    for _, player in pairs(game.players) do
        if player then
            local player_table = storage.players[player.index]
            local network = player.force.find_logistic_network_by_position(player.position, player.surface)
            if not player_table.network or not player_table.network.valid or not network or
                player_table.network.network_id ~= network.network_id then
                -- Clear the history when we change networks
                storage.delivery_history = {}
                player_table.network = network
            end
            if network then
                bots_total = bots_total + network.all_logistic_robots
                bots_available = bots_available + network.available_logistic_robots
                for _, cell in pairs(network.cells) do
                    if cell.valid then
                        bots_charging = bots_charging + cell.charging_robot_count
                        bots_waiting_for_charge = bots_waiting_for_charge + cell.to_charge_robot_count
                    end
                end
                if  not player_table.stopped then
                    counted = 0
                    for _, bot in pairs(network.logistic_robots) do
                            -- counted = counted + 1
                            -- if counted > 300 then
                            --     break
                            -- end
                        if bot.valid and table_size(bot.robot_order_queue) > 0 then
                            order = bot.robot_order_queue[1]
                            -- Record order, deliver, etc
                            storage.bot_items[order.type] = (storage.bot_items[order.type] or 0) + 1
                            local item_name = order.target_item.name.name
                            local item_count = order.target_count
                            local quality = order.target_item.quality.name
                            -- For Deliveries, record the item 
                            if order.type == defines.robot_order_type.deliver and item_name then
                                add_bot_to_bot_deliveries(bot, item_name, quality, item_count)
                                if player_table.settings.show_history then
                                    add_bot_to_active_deliveries(bot, item_name, quality, item_count)
                                end
                            end

                        end
                    end
                end
                -- Remove orders no longer active from the list and add to history
                if player_table.settings.show_history then
                    manage_active_deliveries_history()
                end
            end -- if network
        end
    end
    storage.bot_items["logistic-robot-total"] = bots_total
    storage.bot_items["logistic-robot-available"] = bots_available
    storage.bot_items["charging-robot"] = bots_charging
    storage.bot_items["waiting-for-charge-robot"] = bots_waiting_for_charge
end

return bot_counter