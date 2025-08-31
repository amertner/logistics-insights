--- Central scheduler for periodic per-player and global tasks.
--- Tasks can be registered with a fixed interval (in ticks) and optional pause capability key.

local scheduler = {}

local player_data = require("scripts.player-data")
local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local capability_manager = require("scripts.capability-manager")

---@class SchedulerTask
---@field name string Unique task name
---@field interval number Interval in ticks
---@field per_player boolean If true, runs once per player (fn(player, player_table)), else global (fn())
---@field fn function The function to execute
---@field last_run number Last tick run (for global tasks)
---@field capability string|nil Optional pause capability key. If set and the capability is paused for the player (per_player tasks) the task is skipped without updating last_run.

local global_tasks = {}   ---@type table<string, SchedulerTask>
local player_tasks = {}   ---@type table<string, SchedulerTask>
-- Deterministic execution order (arrays of task names)
local global_task_order = {} ---@type string[]
local player_task_order = {} ---@type string[]
-- Per-player interval overrides: player_index -> task_name -> interval
local player_intervals = {} ---@type table<number, table<string, number>>

--- Register a periodic task.
---@param opts {name:string, interval:number, per_player?:boolean, fn:function, capability?:string}
function scheduler.register(opts)
  if not opts or not opts.name or not opts.interval or not opts.fn then
    error("scheduler.register: missing required fields")
  end
  local task = {
    name = opts.name,
    interval = opts.interval,
    per_player = opts.per_player or false,
    fn = opts.fn,
    last_run = 0,
    capability = opts.capability,
  }
  if task.per_player then
    if not player_tasks[task.name] then
      table.insert(player_task_order, task.name)
    end
    player_tasks[task.name] = task
  else
    if not global_tasks[task.name] then
      table.insert(global_task_order, task.name)
    end
    global_tasks[task.name] = task
  end
end

--- Unregister a task by name.
---@param name string
function scheduler.unregister(name)
  if global_tasks[name] then
    global_tasks[name] = nil
    for i, n in ipairs(global_task_order) do
      if n == name then
        table.remove(global_task_order, i)
        break
      end
    end
  end
  if player_tasks[name] then
    player_tasks[name] = nil
    for i, n in ipairs(player_task_order) do
      if n == name then
        table.remove(player_task_order, i)
        break
      end
    end
  end
end

--- Update interval for an existing task without resetting last_run state.
--- @param name string
--- @param new_interval number
function scheduler.update_interval(name, new_interval)
  local task = global_tasks[name]
  if task then
    task.interval = new_interval
    return
  end
  task = player_tasks[name]
  if task then
    task.interval = new_interval
  end
end

-- Apply global settings to relevant schedules
function scheduler.apply_global_settings()
  -- All players' updates happen on the same schedule
  scheduler.update_interval( "player-bot-chunk", global_data.chunk_interval_ticks() )
  -- On this schedule, update a background network, if applicable
  scheduler.update_interval( "background-refresh", global_data.background_refresh_interval_ticks() )
end

-- Apply player-specific intervals based on current settings.
function scheduler.apply_player_intervals(player_index, player_table)
  assert(player_table.player_index == player_index, "Player table index mismatch")
  scheduler.update_player_intervals(player_index, {
    -- The player's cell update interval depends on how many chunks their network has
    ["player-cell-chunk"] = player_data.cells_chunk_interval(player_table),
    ["ui-update"] = player_data.ui_update_interval(player_table),
  })
end

-- Apply all player intervals based on current settings.
function scheduler.apply_all_player_intervals()
  if not storage.players then return end
  for idx, pt in pairs(storage.players) do
    scheduler.apply_player_intervals(idx, pt)
  end
end

--- Set or update a per-player interval override for a task.
--- @param player_index number
--- @param task_name string
--- @param interval number
function scheduler.update_player_interval(player_index, task_name, interval)
  local task = player_tasks[task_name] or global_tasks[task_name]
  if not task then
    return -- Unknown task; ignore
  end
  -- If interval matches default task interval, remove any override to save memory and simplify logic
  if interval == task.interval then
    local overrides = player_intervals[player_index]
    if overrides then
      overrides[task_name] = nil
    end
    return
  end
  local overrides = player_intervals[player_index]
  if not overrides then
    overrides = {}
    player_intervals[player_index] = overrides
  end
  overrides[task_name] = interval
end

--- Batch update per-player intervals.
--- @param player_index number
--- @param intervals table<string,number>
function scheduler.update_player_intervals(player_index, intervals)
  for name, interval in pairs(intervals) do
    scheduler.update_player_interval(player_index, name, interval)
  end
end
--- Bulk re-register: given a list of task specs, register new ones and update intervals of existing ones.
--- @param specs table[] Each spec: {name, interval, per_player, fn, capability?}
function scheduler.reregister(specs)
  for _, spec in pairs(specs) do
    local existing = (spec.per_player and player_tasks[spec.name]) or (not spec.per_player and global_tasks[spec.name])
    if existing then
      if spec.interval and existing.interval ~= spec.interval then
        existing.interval = spec.interval
      end
      if spec.fn and existing.fn ~= spec.fn then
        existing.fn = spec.fn
      end
      if spec.capability and existing.capability ~= spec.capability then
        existing.capability = spec.capability
      end
      -- Order unchanged for existing tasks
    else
      scheduler.register(spec) -- Adds to order arrays
    end
  end
end

local function run_global_tasks(tick)
  for _, name in ipairs(global_task_order) do
    local task = global_tasks[name]
    if task and (tick - task.last_run) >= task.interval then
      task.last_run = tick
      local ok, err = pcall(task.fn)
      if not ok then
        debugger.error("[scheduler] Task '" .. task.name .. "' failed: " .. tostring(err))
      end
    end
  end
end

  -- Run up to one task for each player
  local function run_player_task(player_index, player_table, player, tick)
    local overrides = player_intervals[player_index] or {}
    for _, name in ipairs(player_task_order) do
      local task = player_tasks[name]
      if task then
        local effective_interval = overrides[task.name] or task.interval
        local last = player_table.schedule_last_run[task.name] or 0
        if effective_interval and (tick - last) >= effective_interval then
          if task.capability then
            if not capability_manager.is_active(player_table, task.capability) then
              -- Skip while inactive (do not advance last_run)
            else
              player_table.schedule_last_run[task.name] = tick
              local ok, err = pcall(task.fn, player, player_table)
              if not ok then
                debugger.error("[scheduler] Player task '" .. task.name .. "' failed for player " .. player_index .. ": " .. tostring(err))
              end
              return
            end
          else
            player_table.schedule_last_run[task.name] = tick
            local ok, err = pcall(task.fn, player, player_table)
            if not ok then
              debugger.error("[scheduler] Player task '" .. task.name .. "' failed for player " .. player_index .. ": " .. tostring(err))
            end
            return
          end
        end
      end
    end
  end

  
--- Run due tasks for this tick.
function scheduler.on_tick()
  local tick = game.tick

  if tick % 120 == 0 then
    -- Check if there are tasks that have not run for too long
    for _, name in ipairs(global_task_order) do
      local task = global_tasks[name]
      if task.last_run + task.interval +20 < tick then
        debugger.error("[scheduler] GTask '" .. task.name .. "' has not run for too long")
      end
    end
  end

  -- Global tasks in deterministic order
  run_global_tasks(tick)

  -- Per-player tasks
  if storage.players then
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player and player.valid and player.connected then
        -- Only run one task per player per tick to spread out load
        run_player_task(player_index, player_table, player, tick)
      end
    end
  end
end

function scheduler.get_registered_tasks_by_tick()
  local tasks = { }
  for _, name in ipairs(global_task_order) do
    local task = global_tasks[name]
    if task then
      tasks[#tasks + 1] = {
        interval = task.interval,
        name = task.name,
        --type = "global"
      }
    end
  end
  for _, name in ipairs(player_task_order) do
    local task = player_tasks[name]
    if task then
      tasks[#tasks + 1] = {
        name = task.name,
        interval = task.interval,
        --type = "player"
      }
    end
  end
  return tasks
end

return scheduler
