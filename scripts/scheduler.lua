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
---@field is_heavy boolean If true, the task is considered heavy. We'll try to avoid running multiple heavy tasks in the same tick.
---@field last_run number Last tick run (for global tasks)
---@field capability string|nil Optional pause capability key. If set and the capability is paused for the player (per_player tasks) the task is skipped without updating last_run.

local global_tasks = {}   ---@type table<string, SchedulerTask>
local player_tasks = {}   ---@type table<string, SchedulerTask>
-- Per-player interval overrides: player_index -> task_name -> interval
local player_intervals = {} ---@type table<number, table<string, number>>

---@class TaskQueue
---@field last_tick number The last tick the queue was built for
---@field items table<number, {player_index: number|nil, task: SchedulerTask}[]> Tasks scheduled for each tick
-- Tasks to run next
local task_queue = {last_tick = 0, items = {}} --@type TaskQueue
local TASK_QUEUE_TICKS = 60 -- How many ticks ahead to queue tasks

--- Register a periodic task.
---@param opts {name:string, interval:number, per_player?:boolean, fn:function, capability?:string, is_heavy?:boolean}
function scheduler.register(opts)
  if not opts or not opts.name or not opts.interval or not opts.fn then
    debugger.error("scheduler.register: missing required fields")
  end
  local task = {
    name = opts.name,
    interval = opts.interval,
    per_player = opts.per_player or false,
    fn = opts.fn,
    is_heavy = opts.is_heavy,
    last_run = 0,
    capability = opts.capability,
  }
  if task.per_player then
    player_tasks[task.name] = task
  else
    global_tasks[task.name] = task
  end
end

--- Unregister a task by name.
---@param name string
function scheduler.unregister(name)
  if global_tasks[name] then
    global_tasks[name] = nil
  end
  if player_tasks[name] then
    player_tasks[name] = nil
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
  -- On this schedule, update a background network, if applicable
  scheduler.update_interval( "background-refresh", global_data.background_refresh_interval_ticks() )
end

-- Apply player-specific intervals based on current settings.
function scheduler.apply_player_intervals(player_index, player_table)
  assert(player_table.player_index == player_index, "Player table index mismatch")
  scheduler.update_player_intervals(player_index, {
    -- The player's cell update interval depends on how many chunks their network has
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

-- Build the task queue for the next TASK_QUEUE_TICKS ticks, starting at first_tick.
-- Tries to avoid scheduling too many heavy tasks in the same tick.
---@param first_tick number The first tick to build the queue for
local function build_task_queue(first_tick)
  task_queue.items = {}
  task_queue.last_tick = first_tick + TASK_QUEUE_TICKS - 1
  local heavy_task_count = 0
  -- Initialise empty lists
  for tick = first_tick, task_queue.last_tick do
    task_queue.items[tick] = {}
  end

  -- Pass 1: Add all tasks to their default ticks
  -- Add global tasks to the tick
  for name, task in pairs(global_tasks) do
    for tick = first_tick, task_queue.last_tick do
      if tick % task.interval == 0 then
        table.insert(task_queue.items[tick], {player_index = nil, task = task})
        if task.is_heavy then
          heavy_task_count = heavy_task_count + 1
        end
      end
    end
  end

  -- Add player tasks
  for player_index, player_table in pairs(storage.players) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected then
      local overrides = player_intervals[player_index] or {}
      for tick = first_tick, task_queue.last_tick do
        for name, task in pairs(player_tasks) do
          local effective_interval = overrides[name] or task.interval
          if tick % effective_interval == 0 then
            table.insert(task_queue.items[tick], {player_index = player_index, task = task})
            if task.is_heavy then
              heavy_task_count = heavy_task_count + 1
            end
          end
        end
      end
    end
  end

  -- Pass 2: Delay excess heavy tasks to a later tick
  local max_heavy_per_tick = math.max(1, math.ceil(heavy_task_count / TASK_QUEUE_TICKS))
  local excess_heavy_tasks = {}
  for tick = first_tick, task_queue.last_tick do
    local items = task_queue.items[tick]
    local heavies = 0
    for i = 1, #items do
      if items[i].task.is_heavy then
        heavies = heavies + 1
        if heavies > max_heavy_per_tick then
          excess_heavy_tasks[#excess_heavy_tasks + 1] = items[i]
          items[i] = nil -- Mark for removal
        end
      end
    end
    if heavies < max_heavy_per_tick and #excess_heavy_tasks > 0 then
      -- Move some excess heavy tasks to this tick
      local can_take = max_heavy_per_tick - heavies
      for i = 1, can_take do
        if #excess_heavy_tasks > 0 then
          local item = table.remove(excess_heavy_tasks, 1)
          items[#items + 1] = item
        end
      end
    end
  end

  -- Pass 3: Add any excess heavy tasks to the last tick. Yuck, but what can we do? Hopefully rare.
  local last_items = task_queue.items[task_queue.last_tick]
  for _, item in pairs(excess_heavy_tasks) do
    last_items[#last_items + 1] = item
  end
end

--- Run due tasks for this tick.
function scheduler.on_tick()
  local tick = game.tick
  if tick > task_queue.last_tick then
    build_task_queue(tick)
  end
  local tasks = task_queue.items[tick]
  if tasks and table_size(tasks) > 0 then
    -- Execute tasks queued for this tick
    for _, taskjob in pairs(tasks) do
      local player_index = taskjob.player_index
      local task = taskjob.task
      if player_index then
        local player_table = storage.players[player_index]
        local player = game.get_player(player_index)
        if player and player.valid and player.connected and player_table then
          local run_task = true
          if task.capability then
            if not capability_manager.is_active(player_table, task.capability) then
              -- Skip while inactive (do not advance last_run)
              run_task = false
            end
          end
          if run_task then
            task.last_run = tick
            debugger.info("[scheduler] Running player task '" .. task.name .. "' for player " .. player_index)
            local ok, err = pcall(task.fn, player, player_table)
            if not ok then
              debugger.error("[scheduler] Player task '" .. task.name .. "' failed for player " .. player_index .. ": " .. tostring(err))
            end
          end
        end
      else
        task.last_run = tick
        debugger.info("[scheduler] Running task " .. task.name)
        local ok, err = pcall(task.fn)
        if not ok then
          debugger.error("[scheduler] Task '" .. task.name .. "' failed: " .. tostring(err))
        end
      end
    end
  end
end

return scheduler
