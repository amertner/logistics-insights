--- A few files to help with debugging
local debugger = {}

-- This level of message will be added to the Factorio log
debugger.debug_level = 1 -- 0 = none, 1 = errors, 2 = warnings, 3 = info, 4 = debug

local function message(level, msg)
  if debugger.debug_level >= level then
    local tickstr = tostring(game.tick)
    local prefix = "DEBUG"
    if level == 1 then
      prefix = "ERROR"
    elseif level == 2 then
      prefix = "WARN"
    elseif level == 3 then
      prefix = "INFO"
    end
    log(tickstr .. ": [" .. prefix .. "] " .. tostring(msg))
  end
end

function debugger.error(msg)
  message(1, msg)
end

function debugger.warn(msg)
  message(2, msg)
end

function debugger.info(msg)
  message(3, msg)
end

function debugger.debug(msg)
  message(4, msg)
end

function debugger.set_level(level)
  debug_level = level
end

-- Dump key storages to files for debugging
function debugger.dump_storage_to_disk()
  helpers.write_file("player.json", helpers.table_to_json(storage.players))
  for _, nwd in pairs(storage.networks) do
    local name = "network-"..nwd.id..".json"
    helpers.write_file(name, helpers.table_to_json(nwd))
  end
  if storage.analysis_state then
    helpers.write_file("analysis_state.json", helpers.table_to_json(storage.analysis_state))
  end
end

return debugger