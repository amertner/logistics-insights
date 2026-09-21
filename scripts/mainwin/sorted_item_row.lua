--- Manage a row of sorted items in the main window
local sorted_item_row = {}

local player_data = require("scripts.player-data")
local mini_button = require("scripts.mainwin.mini_button")
local progress_bars = require("scripts.mainwin.progress_bars")
local utils         = require("scripts.utils")
local network_data  = require("scripts.network-data")

local pairs = pairs
local table_sort = table.sort
local math_floor = math.floor
local math_min = math.min

-- The generation of a row that has been blanked. No real generation can collide with it: they are
-- numbers, or the Longest trip row's "<number>|<item key>"
local CLEARED = "cleared"

--- The average and median trip of an item, as a tooltip line
--- @param entry DeliveredItems
--- @return LocalisedString
local function trip_average_line(entry)
  local median, known = network_data.median_trip(entry)
  if median then
    -- Trips whose length is only a guess are left out of the median, so say what it rests on when
    -- that is not all of them: a median above the average would otherwise look like a mistake
    if known < (entry.dist_count or 0) then
      return {"item-row.trip-average-median-known-1avg-2median-3count",
        utils.format_distances({entry.avg_dist}), utils.format_distances({median}), known}
    end
    return {"item-row.trip-average-median-1avg-2median",
      utils.format_distances({entry.avg_dist}), utils.format_distances({median})}
  end
  -- No trip of known length yet, or history from before the median was tracked
  return {"item-row.trip-average-1avg", utils.format_distances({entry.avg_dist})}
end

--- Add a sorted item row (deliveries, totals, distance carried or longest trip) to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
--- @param title string The title/key for this row type
--- @param button_title string|nil What the button refers to ("history", "delivery", or nil)
--- @param need_progressbar boolean Whether this row needs a progress bar
--- @return LuaGuiElement|unknown|nil The button element, if created
function sorted_item_row.add(player_table, gui_table, title, button_title, need_progressbar)
  player_data.register_ui(player_table, title)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical",
    style = "li_row_vflow"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal",
    style= "li_row_hflow"
  }

  -- Add left-aligned label
  hcell.add {
    type = "label",
    caption = {"item-row." .. title .. "-title"},
    style = "li_row_label",
    tooltip = {"", {"item-row." .. title .. "-tooltip"}}
  }

  local row_button, tip = nil, nil
  if button_title then
    if button_title == "clear" then
      tip = {"item-row.clear-history-tooltip"}
      row_button = mini_button.add(player_table, hcell, button_title, tip, "trash")
    end
  end

  if need_progressbar then
    progress_bars.add_progress_indicator(player_table, cell, title)
  end

  player_table.ui[title].cells = {}
  for count = 1, player_table.settings.max_items do
    player_table.ui[title].cells[count] = gui_table.add {
      name = "logistics-insights-" .. button_title .. "/" .. count,
      type = "sprite-button",
      style = "slot_button",
      enabled = false,
      raise_hover_events = true,
    }
  end
  return row_button
end -- add

--- Display item sprites and numbers in sort order
--- @param player_table PlayerData The player's data table
--- @param title string The title/key for this row type
--- @param all_entries table<string, DeliveryItem|DeliveredItems> All entries to sort and display
--- @param sort_fn function(a, b): boolean Sorting function to determine order
--- @param number_field string The field name to display as number ("count", "dist_sum", "top_dist")
--- @param show_click_tip LocalisedString|fun(entry: table): LocalisedString|nil String to show if the cell is clickable, or a function giving each entry's string
--- @param generation number|string|nil Optional generation counter; skips update if unchanged since last call
function sorted_item_row.update(player_table, title, all_entries, sort_fn, number_field, show_click_tip, generation)
  local ui = player_table.ui[title]
  -- Nothing to draw into: the row is not on screen, so it has not shown this generation either
  if not ui or not ui.cells then
    return
  end
  -- Skip the update if the data has not changed since the row was drawn
  if generation and ui.last_gen == generation then
    return
  end

  --- Generate tooltip text for a cell based on the entry data and number field type
  --- @param entry DeliveryItem|DeliveredItems|UndersupplyItem The entry containing item data
  --- @return LocalisedString The formatted tooltip for the cell
  local function getcelltooltip(entry)
    local tip
    local localised = utils.get_localised_names(entry)
    if number_field == "count" then
      tip = {"", {"item-row.count-field-tooltip-1count-2quality-3itemname", entry.count, localised.qname, localised.iname}}
    elseif number_field == "dist_sum" then
      tip = {"", {"item-row.distance-field-tooltip-1quality-2itemname-3total-4trips-5average",
        localised.qname, localised.iname, utils.format_distances({entry.dist_sum}), entry.dist_count,
        trip_average_line(entry)}}
    elseif number_field == "top_dist" then
      local trips = entry.top_trips or {}
      -- An estimated trip is marked "~", here and wherever else its distance is shown
      local estimated = { trips[1] and not trips[1].exact }
      -- List the runners-up when there are any; the title already carries the longest
      local list = ""
      if #trips > 1 then
        local dists, guessed = {}, {}
        for i = 2, #trips do
          dists[i - 1] = trips[i].dist
          guessed[i - 1] = not trips[i].exact
        end
        list = {"", "\n", {"item-row.trip-list-1dists", utils.format_distances(dists, nil, guessed)}}
      end
      local exact = entry.dist_exact or 0
      -- Only spell out measured vs estimated when the trips are a mix of both
      local coverage
      if exact == entry.dist_count then
        coverage = {"item-row.trip-count-1count", entry.dist_count}
      elseif exact == 0 then
        coverage = {"item-row.trip-all-estimated-1count", entry.dist_count}
      else
        coverage = {"item-row.trip-coverage-1exact-2count", exact, entry.dist_count}
      end
      -- The list leaves out ignored destinations; the statistics don't, so say which is which.
      -- max_dist is the only figure that counts them, so name it when it beats what is listed:
      -- that is exactly when the ignore list is hiding a longer trip than the row shows
      local ignored = ""
      if (entry.ignored_count or 0) > 0 then
        local max_dist = entry.max_dist or 0
        if max_dist > (entry.top_dist or 0) then
          ignored = {"", "\n", {"item-row.trip-ignored-longer-1count-2max", entry.ignored_count,
            utils.format_distances({max_dist})}}
        else
          ignored = {"", "\n", {"item-row.trip-ignored-1count", entry.ignored_count}}
        end
      end
      tip = {"", {"item-row.maxdist-field-tooltip-1max-2list-3average-4coverage-5ignored-6quality-7itemname",
        utils.format_distances({entry.top_dist}, nil, estimated), list, trip_average_line(entry),
        coverage, ignored, localised.qname, localised.iname}}
    elseif number_field == "shortage" then
      tip = {"", {"undersupply-row.shortage-tooltip-1shortage_2item_3quality_4requested_5storage_6underway",
        entry.shortage, localised.iname, localised.qname, entry.request, entry.supply, entry.under_way}}
    end
    if show_click_tip then
      -- Add a click tip if provided
      local click_tip = type(show_click_tip) == "function" and show_click_tip(entry) or show_click_tip
      tip = {"", tip, "\n", click_tip}
    end
    return tip
  end

  -- Count entries, but only up to max_items+1 (we just need to know if there are more)
  local max_items = player_table.settings.max_items
  local entry_count = 0
  for _ in pairs(all_entries) do
    entry_count = entry_count + 1
    if entry_count > max_items then break end
  end

  -- Only create as large an array as needed for display
  local max_needed = math_min(entry_count, max_items)
  local sorted_entries = {}

  if entry_count <= max_needed then
    local idx = 1
    for _, entry in pairs(all_entries) do
      sorted_entries[idx] = entry
      idx = idx + 1
    end
    table_sort(sorted_entries, sort_fn)
  else
    -- For large collections, maintain a sorted top-N list
    local idx = 1
    for _, entry in pairs(all_entries) do
      if idx <= max_needed then
        sorted_entries[idx] = entry
        idx = idx + 1
      else
        -- Once we have max_needed items, sort them
        if idx == max_needed + 1 then
          table_sort(sorted_entries, sort_fn)
          idx = idx + 1 -- Increment to avoid re-sorting
        end
        
        -- Check if this entry belongs in our top-N
        if sort_fn(entry, sorted_entries[max_needed]) then
          -- Find insertion point (binary search would be more efficient for large max_needed)
          local insert_pos = max_needed
          while insert_pos > 1 and sort_fn(entry, sorted_entries[insert_pos-1]) do
            insert_pos = insert_pos - 1
          end
          
          -- Shift elements to make room
          for j = max_needed, insert_pos + 1, -1 do
            sorted_entries[j] = sorted_entries[j-1]
          end
          
          -- Insert the new element
          sorted_entries[insert_pos] = entry
        end
      end
    end
  end

  -- Add up to max_items entries
  local count = 0
  local cells = ui.cells
  for _, entry in ipairs(sorted_entries) do
    if count >= max_items then break end
    -- Sorted highest first, so the rest have nothing to show either. This is what keeps items
    -- with no trip distance out of the two distance rows
    if (entry[number_field] or 0) <= 0 then break end
    local cell = cells[count + 1]
    if cell and cell.valid then
      cell.sprite = utils.get_valid_sprite_path("item/", entry.item_name)
      cell.quality = entry.quality_name or "normal"
      local number = entry[number_field]
      if number_field == "top_dist" or number_field == "dist_sum" then
        number = math_floor(number + 0.5) -- Whole tiles; fractions are noise on a slot button
      end
      cell.number = number
      cell.tooltip = getcelltooltip(entry)
      cell.enabled = true
    end
    count = count + 1
  end

  -- Pad with blank elements
  while count < max_items do
    local cell = cells[count + 1]
    if cell and cell.valid then
      cell.sprite = ""
      cell.tooltip = ""
      cell.number = nil
      cell.enabled = false
    end
    count = count + 1
  end

  -- Drawn, so this generation is now what the row shows
  ui.last_gen = generation
end -- update

--- Clear all cells in a sorted item row
---@param player_table PlayerData The player's data table
---@param title string The title/key for this row type
function sorted_item_row.clear_cells(player_table, title)
  local ui = player_table.ui[title]
  if not ui or not ui.cells then
    return
  end
  -- A row with no network to draw from is cleared on every update, so say that it is already
  -- blank rather than writing the same nothing into every cell a second time. Recording it as a
  -- generation of its own is what stops the next real update being skipped
  if ui.last_gen == CLEARED then
    return
  end
  ui.last_gen = CLEARED
  for i = 1, player_table.settings.max_items do
    local cell = ui.cells[i]
    if cell and cell.valid then
      cell.sprite = ""
      cell.tooltip = ""
      cell.number = nil
      cell.enabled = false
    end
  end
end

return sorted_item_row