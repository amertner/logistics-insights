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

local TAGS_FOLLOW = { follow = true }
local TAGS_EMPTY = {}

--- The average and median haul of an item, as a tooltip line
--- @param entry DeliveredItems
--- @return LocalisedString
local function haul_average_line(entry)
  local average = math_floor(entry.avg_dist + 0.5)
  local median = network_data.median_haul(entry)
  if median then
    return {"item-row.haul-average-median-1avg-2median", average, math_floor(median + 0.5)}
  end
  return {"item-row.haul-average-1avg", average} -- History from before the median was tracked
end

--- Add a sorted item row (deliveries, totals, distance carried or longest haul) to the GUI
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
      row_button = mini_button.add(player_table, hcell, button_title, tip, "trash", false)
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
--- @param clearing boolean Whether this update is due to clearing history
--- @param show_click_tip LocalisedString|fun(entry: table): LocalisedString|nil String to show if the cell is clickable, or a function giving each entry's string
--- @param generation number|string|nil Optional generation counter; skips update if unchanged since last call
function sorted_item_row.update(player_table, title, all_entries, sort_fn, number_field, clearing, show_click_tip, generation)
  -- Skip update if data generation hasn't changed since last render
  if generation and player_table.ui[title] then
    if player_table.ui[title].last_gen == generation then
      return
    end
    player_table.ui[title].last_gen = generation
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
      tip = {"", {"item-row.distance-field-tooltip-1quality-2itemname-3total-4hauls-5average",
        localised.qname, localised.iname, utils.format_short_number(entry.dist_sum), entry.dist_count,
        haul_average_line(entry)}}
    elseif number_field == "top_dist" then
      local hauls = entry.top_hauls or {}
      local estimated = hauls[1] and not hauls[1].exact and {"item-row.haul-estimated-suffix"} or ""
      -- List the longest hauls when there is more than one
      local list = ""
      if #hauls > 1 then
        local dists = {}
        for i, haul in ipairs(hauls) do
          dists[i] = math_floor(haul.dist + 0.5)
        end
        list = {"", "\n", {"item-row.haul-list-1dists", table.concat(dists, ", ")}}
      end
      local exact = entry.dist_exact or 0
      -- Only spell out measured vs estimated when the hauls are a mix of both
      local coverage
      if exact == entry.dist_count then
        coverage = {"item-row.haul-count-1count", entry.dist_count}
      elseif exact == 0 then
        coverage = {"item-row.haul-all-estimated-1count", entry.dist_count}
      else
        coverage = {"item-row.haul-coverage-1exact-2count", exact, entry.dist_count}
      end
      -- The list leaves out ignored destinations; the statistics don't, so say which is which
      local ignored = ""
      if (entry.ignored_count or 0) > 0 then
        ignored = {"", "\n", {"item-row.haul-ignored-1count", entry.ignored_count}}
      end
      tip = {"", {"item-row.maxdist-field-tooltip-1max-2estimated-3list-4average-5coverage-6ignored-7quality-8itemname",
        math_floor(entry.top_dist + 0.5), estimated, list, haul_average_line(entry),
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
  for _, entry in ipairs(sorted_entries) do
    if count >= player_table.settings.max_items then break end
    if not player_table.ui[title] or not player_table.ui[title].cells then break end
    local cell = player_table.ui[title].cells[count + 1]
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
      if show_click_tip then
        cell.tags = TAGS_FOLLOW
      else
        cell.tags = TAGS_EMPTY
      end
    end
    count = count + 1
  end

  -- Pad with blank elements
  while count < player_table.settings.max_items do
    if not player_table.ui[title] or not player_table.ui[title].cells then break end
    local cell = player_table.ui[title].cells[count + 1]
    if cell and cell.valid then
      cell.sprite = ""
      cell.tooltip = ""
      cell.number = nil
      cell.enabled = false
    end
    count = count + 1
  end
end -- update

--- Clear all cells in a sorted item row
---@param player_table PlayerData The player's data table
---@param title string The title/key for this row type
function sorted_item_row.clear_cells(player_table, title)
  if not player_table.ui[title] or not player_table.ui[title].cells then
    return
  end
  for i = 1, player_table.settings.max_items do
    local cell = player_table.ui[title].cells[i]
    if cell and cell.valid then
      cell.sprite = ""
      cell.tooltip = ""
      cell.number = nil
      cell.enabled = false
      cell.tags = TAGS_EMPTY
    end
  end
end

return sorted_item_row