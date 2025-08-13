--- Central scheduler for periodic per-player and global tasks.
--- Tasks can be registered with a fixed interval (in ticks) and optional pause capability key.

local scheduler = {}

local player_data = require("scripts.player-data")

---@class SchedulerTask
---@field name string Unique task name
---@field interval uint Interval in ticks
---@field per_player boolean If true, runs once per player (fn(player, player_table)), else global (fn())
---@field fn function The function to execute
---@field last_run uint Last tick run (for global tasks)
---@field capability string|nil Optional pause capability key (future integration)

local global_tasks = {}   ---@type table<string, SchedulerTask>
local player_tasks = {}   ---@type table<string, SchedulerTask>
-- Per-player interval overrides: player_index -> task_name -> interval
local player_intervals = {} ---@type table<uint, table<string, uint>>

--- Register a periodic task.
---@param opts {name:string, interval:uint, per_player?:boolean, fn:function, capability?:string}
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
    player_tasks[task.name] = task
  else
    global_tasks[task.name] = task
  end
end

--- Unregister a task by name.
---@param name string
function scheduler.unregister(name)
  global_tasks[name] = nil
  player_tasks[name] = nil
end

--- Update interval for an existing task without resetting last_run state.
--- @param name string
--- @param new_interval uint
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

-- Apply player-specific intervals based on current settings.
function scheduler.apply_player_intervals(player_index, player_table)
  assert(player_table.player_index == player_index, "Player table index mismatch")
  scheduler.update_player_intervals(player_index, {
    ["bot-chunk"] = player_data.bot_chunk_interval(player_table),
    ["cell-chunk"] = player_data.cells_chunk_interval(player_table),
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
--- @param player_index uint
--- @param task_name string
--- @param interval uint
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
--- @param player_index uint
--- @param intervals table<string,uint>
function scheduler.update_player_intervals(player_index, intervals)
  for name, interval in pairs(intervals) do
    scheduler.update_player_interval(player_index, name, interval)
  end
end

--- Bulk re-register: given a list of task specs, register new ones and update intervals of existing ones.
--- @param specs table[] Each spec: {name, interval, per_player, fn}
function scheduler.reregister(specs)
  for _, spec in pairs(specs) do
    local existing = (spec.per_player and player_tasks[spec.name]) or (not spec.per_player and global_tasks[spec.name])
    if existing then
      if existing.interval ~= spec.interval then
        existing.interval = spec.interval
      end
      -- Update function reference in case it changed
      if existing.fn ~= spec.fn then
        existing.fn = spec.fn
      end
    else
      scheduler.register(spec)
    end
  end
end

--- Run due tasks for this tick.
function scheduler.on_tick()
  local tick = game.tick
  -- Global tasks
  for _, task in pairs(global_tasks) do
    if tick - task.last_run >= task.interval then
      task.last_run = tick
      local ok, err = pcall(task.fn)
      if not ok then
        log("[scheduler] Task '" .. task.name .. "' failed: " .. tostring(err))
      end
    end
  end
  -- Per-player tasks
  if storage.players then
    for player_index, player_table in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player and player.valid then
        local overrides = player_intervals[player_index] or {}
        for _, task in pairs(player_tasks) do
          local effective_interval = task.interval
          if overrides[task.name] then
            effective_interval = overrides[task.name]
          end
          local last = player_table.schedule_last_run[task.name] or 0
          if effective_interval and tick - last >= effective_interval then
            player_table.schedule_last_run[task.name] = tick
            local ok, err = pcall(task.fn, player, player_table)
            if not ok then
              log("[scheduler] Player task '" .. task.name .. "' failed for player " .. player_index .. ": " .. tostring(err))
            end
          end
        end
      end
    end
  end
end

return scheduler
