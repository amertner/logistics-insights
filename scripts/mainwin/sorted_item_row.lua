--- Manage a row of sorted items in the main window
sorted_item_row = {}

local player_data = require("scripts.player-data")

local pairs = pairs
local table_sort = table.sort
local math_floor = math.floor
local math_min = math.min

--- Add a sorted item row (deliveries, totals, or average ticks) to the GUI
--- @param player_table PlayerData The player's data table
--- @param gui_table LuaGuiElement The GUI table to add the row to
--- @param title string The title/key for this row type
--- @param button_title string|nil Optional button type ("startstop", "clear", or nil)
--- @param need_progressbar boolean Whether this row needs a progress bar
function sorted_item_row.add(player_table, gui_table, title, button_title, need_progressbar)
  player_data.register_ui(player_table, title)

  local cell = gui_table.add {
    type = "flow",
    direction = "vertical"
  }
  local hcell = cell.add {
    type = "flow",
    direction = "horizontal"
  }
  hcell.style.horizontally_stretchable = true

  -- Add left-aligned label
  hcell.add {
    type = "label",
    caption = {"item-row." .. title .. "-title"},
    style = "heading_2_label",
    tooltip = {"", {"item-row." .. title .. "-tooltip"}}
  }

  if button_title then
    -- Add flexible spacer that pushes button to the right
    local space = hcell.add {
      type = "empty-widget",
      style = "draggable_space",
      name = "spacer" .. title,
    }
    space.style.horizontally_stretchable = true

    -- Determine the sprite based on button type and current state
    local sprite, tip
    if button_title == "startstop" then
      sprite = "li_pause"
      tip = {"item-row.toggle-gathering-tooltip"}
    elseif button_title == "clear" then
      sprite = "utility/trash"
      tip = {"item-row.clear-history-tooltip"}
    end

    -- Add right-aligned button that's vertically centered with the label
    local row_button = hcell.add {
      type = "sprite-button",
      style = "mini_button", -- Small button size
      sprite = sprite,
      name = "logistics-insights-sorted-" .. button_title,
      tooltip = tip
    }

    -- Make button vertically centered with a small top margin for alignment
    row_button.style.top_margin = 2
    hcell.style.vertical_align = "center"
    if button_title == "startstop" then
      player_table.ui.startstop = row_button
    end
  end

  if need_progressbar then
    local progressbar = cell.add {
      type = "progressbar",
      name = title .. "_progressbar",
    }
    progressbar.style.horizontally_stretchable = true
    player_table.ui[title].progressbar = progressbar
  end

  player_table.ui[title].cells = {}
  for count = 1, player_table.settings.max_items do
    player_table.ui[title].cells[count] = gui_table.add {
      type = "sprite-button",
      style = "slot_button",
      enabled = false,
    }
  end
end -- add

--- Display item sprites and numbers in sort order
--- @param player_table PlayerData The player's data table
--- @param title string The title/key for this row type
--- @param all_entries table<string, DeliveryItem|DeliveredItems> All entries to sort and display
--- @param sort_fn function(a, b): boolean Sorting function to determine order
--- @param number_field string The field name to display as number ("count", "ticks", "avg")
--- @param clearing boolean Whether this update is due to clearing history
function sorted_item_row.update(player_table, title, all_entries, sort_fn, number_field, clearing)

  --- Generate tooltip text for a cell based on the entry data and number field type
  --- @param entry DeliveryItem|DeliveredItems The entry containing item data
  --- @return LocalisedString The formatted tooltip for the cell
  local function getcelltooltip(entry)
    local tip
    local quality = entry.localised_quality_name or entry.quality_name
    local name = entry.localised_name or entry.item_name
    if number_field == "count" then
      tip = {"", {"item-row.count-field-tooltip-1count-2quality-3itemname", entry.count, quality, name}}
    elseif number_field == "ticks" then
      tip = {"", {"item-row.ticks-field-tooltip-1ticks-2count-3quality-4itemname", entry.ticks, entry.count, quality, name}}
    elseif number_field == "avg" then
      local int_part = math_floor(entry.avg)
      local decimal_part = math_floor((entry.avg - int_part) * 10 + 0.5)
      local ticks_formatted = int_part .. "." .. decimal_part
      tip = {"", {"item-row.avg-field-tooltip-1ticks-2count-3quality-4itemname", ticks_formatted, entry.count, quality, name}}
    elseif number_field == "shortage" then
      tip = {"", {"undersupply-row.shortage-tooltip-1shortage_2item_3quality_4requested_5storage_5underway",
        entry.shortage, name, quality, entry.request, entry.supply, entry.under_way}}
    end
    return tip
  end

  -- If paused, just disable all the fields, unless we just cleared history
  if player_data.is_paused(player_table) and not clearing then
    if not player_table.ui[title] or not player_table.ui[title].cells then
      return
    end
    for i = 1, player_table.settings.max_items do
      local cell = player_table.ui[title].cells[i]
      if cell and cell.valid then
        cell.enabled = false
      end
    end
    return
  end

  -- Pre-allocate array by counting entries first
  local entry_count = 0
  for _ in pairs(all_entries) do
    entry_count = entry_count + 1
  end

  -- Only create as large an array as needed for display
  local max_needed = math_min(entry_count, player_table.settings.max_items)
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
      cell.sprite = "item/" .. entry.item_name
      cell.quality = entry.quality_name or "normal"
      cell.number = entry[number_field]
      cell.tooltip = getcelltooltip(entry)
      cell.enabled = not player_data.is_paused(player_table)
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

return sorted_item_row