--- Central scheduler for periodic per-player and global tasks.
--- Tasks can be registered with a fixed interval (in ticks)

local scheduler = {}

local player_data = require("scripts.player-data")
local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local bench_profiler = require("scripts.bench-profiler")
local DEBUG_ENABLED_INFO = debugger.debug_level > 1
local PROFILING = debugger.PROFILING

---@class SchedulerTask
---@field name string Unique task name
---@field interval number Interval in ticks
---@field per_player boolean If true, runs once per player (fn(player, player_table)), else global (fn())
---@field fn function The function to execute
---@field is_heavy boolean If true, the task is considered heavy. We'll try to avoid running multiple heavy tasks in the same tick.
---@field last_run number Last tick run (for global tasks)

local global_tasks = {}   ---@type table<string, SchedulerTask>
local player_tasks = {}   ---@type table<string, SchedulerTask>
-- Per-player interval overrides: player_index -> task_name -> interval
local player_intervals = {} ---@type table<number, table<string, number>>
-- Tick offset for phase alignment (normally 0; tests can set this to game.tick to get deterministic scheduling)
local tick_offset = 0

---@class TaskQueue
---@field last_tick number The last tick the queue was built for
---@field items table<number, {player_index: number|nil, task: SchedulerTask}[]> Tasks scheduled for each tick
-- Tasks to run next
local task_queue = {last_tick = 0, items = {}} --@type TaskQueue
local TASK_QUEUE_TICKS = 60 -- How many ticks ahead to queue tasks

--- Register a periodic task.
---@param opts {name:string, interval:number, per_player?:boolean, fn:function, is_heavy?:boolean}
function scheduler.register(opts)
  if not opts or not opts.name or not opts.interval or not opts.fn then
    debugger.error("scheduler.register: missing required fields")
  end
  -- Bench profiler interval override hook. When the harness wants to disable
  -- a task during a benchmark (to isolate one heavy task from another), it
  -- sets bench_profiler.task_interval_overrides[name] to a very large number.
  -- Patching here is the cleanest hook because bench-overrides.lua loads before
  -- any register() call, and we don't need any on_init / runtime gymnastics.
  if bench_profiler.enabled and bench_profiler.task_interval_overrides then
    local override = bench_profiler.task_interval_overrides[opts.name]
    if override then
      opts.interval = override
    end
  end
  local task = {
    name = opts.name,
    interval = opts.interval,
    per_player = opts.per_player or false,
    fn = opts.fn,
    is_heavy = opts.is_heavy,
    last_run = 0,
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
      if (tick - tick_offset) % task.interval == 0 then
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
          if (tick - tick_offset) % effective_interval == 0 then
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

  -- Pass 3: Distribute remaining excess heavy tasks round-robin across all
  -- ticks in the queue, instead of dumping them all on the last tick. This
  -- still doesn't guarantee staying under max_heavy_per_tick (if the queue
  -- is genuinely full there's nothing we can do), but it spreads the damage
  -- evenly rather than creating one fat spike tick that dominates p99.
  local overflow_count = #excess_heavy_tasks
  if overflow_count > 0 then
    local rr_tick = first_tick
    for _, item in pairs(excess_heavy_tasks) do
      local items = task_queue.items[rr_tick]
      items[#items + 1] = item
      rr_tick = rr_tick + 1
      if rr_tick > task_queue.last_tick then rr_tick = first_tick end
    end
  end

  -- Diagnostic: when bench profiling is enabled, record per-queue stats so we
  -- can correlate per-tick spikes with the queue that scheduled them. Counts
  -- "heavy slots" (a heavy task scheduled to fire on a tick), not actual run
  -- time. This runs once per 60 ticks, costs ~60 table reads, and only happens
  -- when bench profiler is active.
  if bench_profiler.enabled then
    local max_heavy, max_heavy_tick = 0, first_tick
    for tick = first_tick, task_queue.last_tick do
      local items = task_queue.items[tick]
      local h = 0
      for _, it in pairs(items) do
        if it.task.is_heavy then h = h + 1 end
      end
      if h > max_heavy then
        max_heavy = h
        max_heavy_tick = tick
      end
    end
    bench_profiler.record_queue(first_tick, task_queue.last_tick, max_heavy, max_heavy_tick, overflow_count)
  end
end

--- Run due tasks for this tick.
function scheduler.on_tick()
  local tick = game.tick
  if tick > task_queue.last_tick then
    local profiler
    if PROFILING then profiler = helpers.create_profiler() end
    build_task_queue(tick)
    if PROFILING then
      profiler.stop()
      log({"", "[perf] build_task_queue ", profiler})
    end
  end
  local tasks = task_queue.items[tick]
  if tasks and next(tasks) then
    -- Execute tasks queued for this tick
    for _, taskjob in pairs(tasks) do
      local player_index = taskjob.player_index
      local task = taskjob.task
      if player_index then
        local player_table = storage.players[player_index]
        local player = game.get_player(player_index)
        if player and player.valid and player.connected and player_table then
          task.last_run = tick
          if DEBUG_ENABLED_INFO then
            debugger.info("[scheduler] Running player task '" .. task.name .. "' for player " .. player_index)
          end
          local profiler
          local needs_timing = PROFILING or bench_profiler.enabled
          if needs_timing then profiler = bench_profiler.start_timing() end
          local ok, err = pcall(task.fn, player, player_table)
          if needs_timing then
            profiler.stop()
            if PROFILING then
              log({"", "[perf] ", task.name, " p", player_index, " ", profiler})
            end
            if bench_profiler.enabled then
              bench_profiler.record(task.name, profiler, task.is_heavy)
            end
          end
          if not ok then
            debugger.error("[scheduler] Player task '" .. task.name .. "' failed for player " .. player_index .. ": " .. tostring(err))
          end
        end
      else
        task.last_run = tick
        if DEBUG_ENABLED_INFO then
          debugger.info("[scheduler] Running task " .. task.name)
        end
        local profiler
        local needs_timing = PROFILING or bench_profiler.enabled
        if needs_timing then profiler = bench_profiler.start_timing() end
        local ok, err = pcall(task.fn)
        if needs_timing then
          profiler.stop()
          if PROFILING then
            log({"", "[perf] ", task.name, " ", profiler})
          end
          if bench_profiler.enabled then
            bench_profiler.record(task.name, profiler, task.is_heavy)
          end
        end
        if not ok then
          debugger.error("[scheduler] Task '" .. task.name .. "' failed: " .. tostring(err))
        end
      end
    end
  end
end

--- Reset scheduler phase to align with the current tick.
--- After calling this, all task intervals are relative to game.tick,
--- making scheduling deterministic regardless of absolute tick.
function scheduler.reset_phase()
  tick_offset = game.tick
  task_queue.last_tick = 0  -- force rebuild on next on_tick
end

return scheduler
