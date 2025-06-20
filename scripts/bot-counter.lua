
bot_counter = {}

function bot_counter.count_bots(game)
    storage.bot_items = {}
    storage.bot_deliveries = {}
    if storage.bot_active_deliveries == nil then
        storage.bot_active_deliveries = {}
    end
    local logi_bots = 0
    local con_bots = 0
    for _, player in pairs(game.players) do
        if player then
            local player_table = storage.players[player.index]
            local network = player.force.find_logistic_network_by_position(player.position, player.surface)
            player_table.network = network -- Store the network in player table for later use
            if network then
                logi_bots = logi_bots + network.available_logistic_robots
                con_bots = con_bots + network.available_construction_robots
                for _, bot in ipairs(network.logistic_robots) do
                    if bot.valid and bot.robot_order_queue then
                        for _, order in pairs(bot.robot_order_queue) do
                            -- Record order, deliver, etc
                            storage.bot_items[order.type] = (storage.bot_items[order.type] or 0) + 1
                            local item_name = order.target_item.name.name
                            local item_count = order.target_count
                            local quality = order.target_item.quality.name
                            local key = item_name .. "-" .. quality
                            -- For Deliveries, record the item 
                            if order.type == defines.robot_order_type.deliver and item_name then
                                if storage.bot_deliveries[key] == nil then
                                    storage.bot_deliveries[key] = {
                                        item_name = item_name,
                                        quality_name = quality,
                                        count = item_count,
                                    }
                                else
                                    storage.bot_deliveries[key].count = storage.bot_deliveries[key].count + item_count
                                end
                                if storage.bot_active_deliveries[bot.unit_number] == nil then
                                    -- Order not seen before
                                    storage.bot_active_deliveries[bot.unit_number] = {
                                        item_name = item_name,
                                        quality_name = quality,
                                        count = item_count,
                                        first_seen = game.tick,
                                        last_seen = game.tick,
                                    }
                                else -- It's still under way
                                    storage.bot_active_deliveries[bot.unit_number].last_seen = game.tick
                                end
                            end
                            break -- only count the first order 
                        end
                    end
                end
            end
        end
    end
    -- Remove orders no longer active from the list and add to history
    for unit_number, order in pairs(storage.bot_active_deliveries) do
        if order.last_seen < game.tick then
            key = order.item_name..order.quality_name
            if storage.delivery_history[key] == nil then
                storage.delivery_history[key] = {
                    item_name = order.item_name,
                    quality_name = order.quality_name,
                    count = 0,
                    ticks = 0,
                }
            end
            history_order = storage.delivery_history[key]
            history_order.count = (history_order.count or 0) + order.count
            ticks = order.last_seen - order.first_seen
            if ticks < 1 then ticks = 1 end
            history_order.ticks = (history_order.ticks or 0) + ticks
            history_order.avg = history_order.ticks / history_order.count
            storage.bot_active_deliveries[unit_number] = nil -- remove from active list
        end
    end
    storage.bot_items["logistic-robot"] = logi_bots
    storage.bot_items["construction-robot"] = con_bots
end

return bot_counter