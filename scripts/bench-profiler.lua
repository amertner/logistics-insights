--- Lightweight in-memory profiler for benchmark sweeps.
---
--- Per-call cost: helpers.create_profiler() + .stop() + .add() + integer increment.
--- No log() calls, no string formatting per call. Once per second the
--- accumulated profilers are emitted as a single log line for the harness
--- to parse after the run.
---
--- Enabled via bench-overrides.lua (which is loaded before scheduler.lua so
--- the scheduler picks up the enabled flag at module load time).

local M = {}

M.enabled = false

--- Number of ticks since the first recorded call after which dump() should fire.
--- When set (by bench-overrides.lua), dump() becomes a one-shot that runs exactly
--- once near the end of the benchmark. When nil, dump() fires on every call,
--- which is the right behavior for manual experimentation outside the harness.
M.dump_after_ticks = nil

--- Tick at which the first instrumented call was recorded. Lazy-captured by record().
M.start_tick = nil

--- One-shot flag set by dump() once it has emitted in deadline mode, so subsequent
--- scheduler invocations are no-ops.
M.dumped = false

--- Reusable scratch profiler. The scheduler calls start_timing() to get this
--- ready-to-time, runs one task, calls stop() and record(). This avoids
--- helpers.create_profiler() being called once per task per tick (~3000+
--- allocations per benchmark run); instead one userdata is created and reused.
M.scratch = nil

--- name -> { count = integer, time = LuaProfiler accumulator }
--- The accumulator is always a fresh zero-initialised stopped profiler created
--- on first record() of each task. We never adopt the caller's profiler as
--- the accumulator because the caller (the scheduler) reuses M.scratch.
M.totals = {}

--- Per-tick distribution tracking. Each unique tick that fires at least one
--- LI task gets one accumulator profiler holding the sum of all task times in
--- that tick. We use a tick-change detector inside record() instead of an
--- explicit on_tick wrapper, so the scheduler doesn't need extra plumbing.
--- Ticks where the mod does no work are not represented at all (zero-cost
--- ticks would just pull p50 down to 0 without telling us anything useful).
M.current_tick = nil
M.current_tick_acc = nil
M.tick_records = {}  -- array of { tick = integer, profiler = LuaProfiler }

--- Diagnostic queue stats. Each queue build (60 ticks worth of scheduling)
--- records its stats here when bench profiler is enabled. The scheduler calls
--- record_queue() at the end of build_task_queue. We dump these at the end so
--- the user can correlate per-tick spikes with the queue that scheduled them.
M.queue_records = {}

--- Per-call records for all tasks. When record() is called and M.track_per_call
--- is set, allocate a fresh profiler holding just that call's time and append
--- it here. Dumped at end as one log line per record.
--- Cost: ~3us per call (allocation + add). At ~5000 calls/run,
--- this is ~15ms total self-overhead spread across all tasks.
M.track_per_call = true
M.per_call_records = {}  -- array of { task = string, tick = integer, profiler = LuaProfiler }

--- Task name -> interval (ticks). Tasks named here have their registered
--- interval replaced at scheduler.register() time. Use a very large value to
--- effectively disable a task during benchmarking, isolating one heavy task
--- from another.
M.task_interval_overrides = {}

--- Append one queue's stats. Called from scheduler.build_task_queue.
--- @param first_tick integer
--- @param last_tick integer
--- @param max_heavy integer Maximum heavy tasks landing on any single tick in this queue
--- @param max_heavy_tick integer The tick where max_heavy occurred
--- @param overflow integer Number of heavy tasks that pass 2 couldn't place and went to pass 3
function M.record_queue(first_tick, last_tick, max_heavy, max_heavy_tick, overflow)
  M.queue_records[#M.queue_records + 1] = {
    first = first_tick,
    last = last_tick,
    max_heavy = max_heavy,
    max_heavy_tick = max_heavy_tick,
    overflow = overflow,
  }
end

--- Returns the reusable scratch profiler, reset to zero and running.
--- Allocates exactly once across the lifetime of the mod.
--- @return LuaProfiler
function M.start_timing()
  local s = M.scratch
  if s then
    s.reset()
    return s
  end
  s = helpers.create_profiler()
  M.scratch = s
  return s
end

--- Record one timed call. The caller is responsible for having stopped the profiler.
--- @param name string Task identifier
--- @param profiler LuaProfiler Stopped profiler measuring one call
--- @param is_heavy boolean? If true and M.track_per_call is true, also keep a
---        per-call record for percentile analysis at dump time.
function M.record(name, profiler, is_heavy)
  if not M.start_tick then M.start_tick = game.tick end

  -- Per-tick bucket: detect tick change and finalize the previous tick.
  -- All task calls within the same tick land in the same accumulator.
  local tick = game.tick
  if M.current_tick ~= tick then
    if M.current_tick_acc then
      M.tick_records[#M.tick_records + 1] = { tick = M.current_tick, profiler = M.current_tick_acc }
    end
    M.current_tick = tick
    M.current_tick_acc = helpers.create_profiler(true)  -- stopped, zero
  end
  M.current_tick_acc.add(profiler)

  local entry = M.totals[name]
  if not entry then
    entry = { count = 0, time = helpers.create_profiler(true) }
    M.totals[name] = entry
  end
  entry.time.add(profiler)
  entry.count = entry.count + 1

  -- Per-call capture for all tasks. We need a fresh profiler we can retain
  -- until dump time, since the caller's profiler is the reused scratch.
  if M.track_per_call then
    local snap = helpers.create_profiler(true)
    snap.add(profiler)
    M.per_call_records[#M.per_call_records + 1] = { task = name, tick = tick, profiler = snap }
  end
end

--- Time one named call by wrapping fn(). Caller-side helper that hides the
--- start_timing/stop/record boilerplate so timed call sites stay one-liners.
--- When bench profiler is disabled, this is a tail call to fn() with one
--- extra boolean check.
--- @param name string Synthetic task name to record under
--- @param fn function Zero-arg function to time
--- @return any Whatever fn() returns
function M.measure(name, fn)
  if not M.enabled then return fn() end
  local p = M.start_timing()
  local result = fn()
  p.stop()
  M.record(name, p, true)
  return result
end

--- Reset all accumulators. Called between benchmark runs if multiple runs share
--- a Factorio process (which we currently avoid by forcing --benchmark-runs 1).
function M.reset()
  M.totals = {}
  M.start_tick = nil
  M.dumped = false
  M.current_tick = nil
  M.current_tick_acc = nil
  M.tick_records = {}
  M.queue_records = {}
  M.per_call_records = {}
end

--- Emit one log line per task containing the accumulated count and time.
---
--- When M.dump_after_ticks is set (the harness path), this is a one-shot:
--- the early-out is just a couple of field reads + an integer comparison
--- (~3us), so calling it once a second from the scheduler costs ~300us
--- across an entire benchmark run, plus one real ~460us emit at the deadline.
--- Total dump self-cost: <1ms instead of ~45ms with per-second emits.
---
--- When M.dump_after_ticks is nil (manual experimentation without the harness),
--- dump() fires on every call as before.
---
--- Factorio localised strings cap parameter count at 20, so a single line
--- containing every task would overflow once we have more than ~3 tasks.
--- Splitting to one line per task keeps each log() call to ~5 parameters.
---
--- The harness groups [libench-dump] lines by tick and uses the highest-tick
--- group as the final cumulative totals.
---
--- Format (one line per task):
---   [libench-dump] tick=<n> task=<name> count=<count> time=<profiler>
---
--- Each <profiler> stringifies to e.g. "Duration: 1.234ms" or "Duration: 456us".
function M.dump()
  if not M.enabled or M.dumped then return end
  if not next(M.totals) then return end
  if M.dump_after_ticks then
    if not M.start_tick or game.tick - M.start_tick < M.dump_after_ticks then
      return  -- Deadline not reached yet.
    end
  end

  -- Sort task names for stable output (easier to diff dumps).
  local names = {}
  for name in pairs(M.totals) do names[#names + 1] = name end
  table.sort(names)

  local tick_str = tostring(game.tick)
  for _, name in ipairs(names) do
    local entry = M.totals[name]
    log({"", "[libench-dump] tick=", tick_str, " task=", name, " count=", tostring(entry.count), " time=", entry.time})
  end

  -- Per-tick distribution. Flush the in-flight tick first, then emit one
  -- log line per recorded tick. We can't read numeric ms out of a LuaProfiler
  -- in pure Lua (tostring() doesn't return the engine's "Duration: Xms"
  -- format — that formatting only happens when a profiler is passed to log()
  -- via the localised-string mechanism), so we let the engine format each
  -- value here and compute percentiles in the harness.
  --
  -- Cost: ~3000 log() calls all emitted within this single dump tick. The
  -- dump tick is the very last instrumented tick of the benchmark and is
  -- discarded by the harness anyway, so this contaminates nothing real.
  if M.current_tick_acc then
    M.tick_records[#M.tick_records + 1] = { tick = M.current_tick, profiler = M.current_tick_acc }
    M.current_tick_acc = nil
  end
  for i = 1, #M.tick_records do
    local rec = M.tick_records[i]
    log({"", "[libench-tick] tick=", tostring(rec.tick), " time=", rec.profiler})
  end

  -- Per-queue diagnostic stats. Format:
  --   [libench-queue] first=<n> last=<n> max_heavy=<n> max_heavy_tick=<n> overflow=<n>
  -- Use string.format here (no profilers in this output, so no need for the
  -- localised-string mechanism).
  for i = 1, #M.queue_records do
    local q = M.queue_records[i]
    log(string.format("[libench-queue] first=%d last=%d max_heavy=%d max_heavy_tick=%d overflow=%d",
      q.first, q.last, q.max_heavy, q.max_heavy_tick, q.overflow))
  end

  -- Per-call records for heavy tasks. One log line per record. The harness
  -- groups by task and computes percentiles. Same trick as the per-tick lines:
  -- everything emits in the dump tick, which is discarded.
  for i = 1, #M.per_call_records do
    local rec = M.per_call_records[i]
    log({"", "[libench-call] task=", rec.task, " tick=", tostring(rec.tick), " time=", rec.profiler})
  end

  if M.dump_after_ticks then M.dumped = true end
end

return M
