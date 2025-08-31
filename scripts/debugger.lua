--- A few files to help with debugging
local debugger = {}

local debug_level = 3 -- 0 = none, 1 = errors, 2 = warnings, 3 = info, 4 = debug

local function message(level, msg)
  if debug_level >= level then
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


return debugger