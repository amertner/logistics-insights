# Benchmark harness

Sweep `logistics-insights` runtime settings against a single Factorio save and record per-tick timings, so you can see how chunk size and other knobs affect performance.

## How it works

Each configuration runs in its own `factorio --benchmark` process. Before each launch the harness writes `bench-overrides.lua` in the mod root; the mod's [scripts/global-data.lua](../scripts/global-data.lua) picks it up at load time via `pcall(require, "bench-overrides")` and replaces accessor functions on `global_data`. This means the overridden values are live from tick 0 — there is no warmup window where in-flight chunks finish on the old settings before the new ones take effect.

`bench-overrides.lua` is gitignored and is removed in a `finally` block, even on Ctrl-C.

## Setup

1. Create a Factorio save you want to benchmark against. A mid-to-late-game base with active logistics traffic gives the most useful signal. Note its path.
2. Make sure no other Factorio instance is running.

### PowerShell (Windows)

3. Copy [bench/configs.local.ps1.example](configs.local.ps1.example) to `bench/configs.local.ps1` and edit:
   - `$FactorioExe` — path to `factorio.exe`
   - `$SaveFile` — absolute path to your save
   - `$FactorioLog` — `factorio-current.log` location (standard install puts it in `%APPDATA%\Factorio\`; portable installs put it next to the exe)
   - `$DisableTasks` — scheduler task names to suppress for the run (see below)
   - `$Configurations` — the list of configurations to sweep
4. `bench/configs.local.ps1` is gitignored. Your edits never appear in `git status` and never need stashing before pulling main. The harness dot-sources it automatically if present.

### Bash (macOS / Linux / Git Bash)

3. Copy [bench/configs.local.sh.example](configs.local.sh.example) to `bench/configs.local.sh` and edit:
   - `FACTORIO_EXE` — path to the Factorio executable (see the example file for common macOS/Windows paths)
   - `SAVE_FILE` — absolute path to your save
   - `FACTORIO_LOG` — `factorio-current.log` location
   - `DISABLE_TASKS` — bash array of scheduler task names to suppress
   - `CONFIGURATIONS` — bash array of space-separated `key=value` strings (see the example file)
4. `bench/configs.local.sh` is gitignored. The harness sources it automatically if present.

## Running

### PowerShell

```powershell
cd <mod folder>
.\bench\run-benchmarks.ps1
```

### Bash

```bash
cd <mod folder>
bash bench/run-benchmarks.sh
# or: chmod +x bench/run-benchmarks.sh && ./bench/run-benchmarks.sh
```

Results are appended to `bench/results.csv` (gitignored). Existing rows are kept so you can compare across sweeps.

When `$EnableBenchProfiler = $true` (the default), the harness also writes `bench/per-task-results.csv` with one row per scheduler task per configuration: `task, count, total_ms, avg_ms_per_call, dump_tick`. The harness passes `dump_after_ticks = BenchmarkTicks - 60` into the override file, so [scripts/bench-profiler.lua](../scripts/bench-profiler.lua) emits exactly **one** group of `[libench-dump]` log lines near the end of the run instead of one per second. This drops the profiler's own self-overhead from ~45 ms to ~1 ms per run. The harness truncates `factorio-current.log` before each run so dumps don't bleed across configurations.

Because the in-memory profiler accumulates state across runs in the same Factorio process, `$BenchmarkRuns` is forced to `1` whenever `$EnableBenchProfiler` is set.

### How the per-task profiling works (and why it's cheap)

The mod's [scripts/scheduler.lua](../scripts/scheduler.lua) is the central dispatcher for all periodic work — bot scanning, cell scanning, undersupply analysis, suggestions, UI updates. When the bench profiler is enabled, every task call is wrapped in `helpers.create_profiler()` / `.stop()` / `bench_profiler.record(...)`. `record()` folds the per-call profiler into a per-task accumulator via `LuaProfiler.add()` and bumps a counter — no `log()`, no string formatting per call. The only output is one cumulative `log()` line per second, parsed by the harness after the run finishes. Overhead is comparable to Factorio's own native profilers.

Tasks instrumented:
- `network-check` — detect when the active player switched networks
- `background-refresh` — periodic non-foreground network scan
- `find-next-player-network` — pick which player network to scan next
- `player-network-bot-chunk` — one chunk of bot counting (the main hot path)
- `player-network-cell-chunk` — one chunk of roboport/cell scanning
- `pick-network-to-analyse` — choose next network for derived analysis
- `run-derived-analysis` — one step of undersupply / suggestions calculation
- `analysis-progress-update` — UI progress bar update
- `ui-update` — full UI refresh
- `clear-caches` — periodic cache cleanup
- `bench-profiler-dump` — the dump itself (so you can see its overhead)

`avg_ms_per_call` is the most useful column for comparing chunk sizes: it shows how expensive a single chunk is at each setting. `count * avg = total_ms` is what dominates the per-tick cost.

### Disabling tasks during a benchmark

Set `$DisableTasks` in the harness to a list of scheduler task names to effectively disable them for the duration of the benchmark. This is implemented by patching `scheduler.register()` at the moment tasks are defined: any task in the list gets its interval replaced with `999999999` ticks, so it never fires within a 6000-tick run.

```powershell
$DisableTasks = @("background-refresh")
```

Use this to isolate the cost of one heavy task from another. With `background-refresh` disabled, every spike attribution row points to `run-derived-analysis` and you can study its per-call distribution without interference. Set `$DisableTasks = @()` to disable nothing.

Available task names: see [scripts/scheduler.lua](../scripts/scheduler.lua) call sites in [control.lua](../control.lua) — `network-check`, `background-refresh`, `clear-caches`, `find-next-player-network`, `player-network-bot-chunk`, `player-network-cell-chunk`, `pick-network-to-analyse`, `run-derived-analysis`, `ui-update`, `analysis-progress-update`, `bench-profiler-dump`.

### Heavy-task per-call distribution (`bench/per-call-stats.csv`)

When `bench_profiler.track_per_call` is true (the default), every call to a task marked `is_heavy = true` in [scripts/scheduler.lua](../scripts/scheduler.lua) gets its own retained `LuaProfiler` snapshot. At the end of the run the harness reads them, computes per-task percentiles (p50/p90/p95/p99/max with the tick of max), and prints one line per heavy task plus a "Spike attribution" section listing every >5 ms tick alongside the heavy task call(s) that landed there. CSV columns: `task, count, p50_ms, p90_ms, p95_ms, p99_ms, max_ms, max_tick`.

This is the right tool for "is the per-call cost distribution bimodal or fat-tailed?" and "which heavy task call caused this spike?". Cost: ~3 µs of self-overhead per heavy call (~4 ms total over a 6000-tick run, concentrated on the heavy tasks).

To disable per-call capture (for the cleanest possible measurement of heavy task averages), add to `bench-overrides.lua`:
```lua
bench_profiler.track_per_call = false
```

### Per-tick distribution (`bench/per-tick-stats.csv`)

Alongside the per-task totals, the harness also writes one row per configuration to `bench/per-tick-stats.csv` with the **distribution of LI's own per-tick cost** (sum of all task times in the same tick). Columns: `active_ticks, p50_ms, p90_ms, p95_ms, p99_ms, max_ms, max_tick, over_5ms, over_10ms, over_50ms`.

This is the right way to investigate spikes. Factorio's `--benchmark` summary reports avg/min/max for the *entire engine + all mods* per tick — so the `max=80ms` you see in the summary line might not be LI at all. The per-tick-stats row tells you LI's own contribution, and the `max_tick` column lets you find the offending tick in the log if you want to dig in. `over_Xms` columns count how often LI spent more than X ms in a single tick, so you can see whether spikes are rare outliers or a frequent problem.

`active_ticks` is the number of ticks in which any LI task fired (ticks with zero LI work are excluded — including them would just push p50 to zero without telling you anything useful).

## Important: what the benchmark cannot see

**The benchmark only measures CPU cost. It is blind to result freshness and result accuracy, both of which strongly favour large chunk sizes.** Drawing optimization conclusions from this CSV alone will lead you to the wrong answer.

A smaller chunk size delays results and makes them less accurate:

- **Staleness.** A network with 300 bots and `chunk_size=400` is fully scanned in one tick — the data is a single coherent snapshot. The same network at `chunk_size=10` takes 30 chunks × 5 ticks = 150 ticks to complete. By the time the last chunk lands, the first chunk's data is ~2.4 seconds old. The UI shows a mix of "now" and "moments ago."
- **Inaccuracy from state changes mid-scan.** Bots move, deliver, get destroyed, switch states between chunks. A bot observed as `picking` in chunk 1 may be observed as `delivering` in chunk 30 — the same bot ends up counted in two states. With a single-tick scan, every bot is observed in exactly one state at exactly one moment. The data is *consistent*.
- **Stale derived analysis.** Undersupply and suggestions analysis runs *after* a scan completes. With small chunks, the scan that fed the analysis is already old by the time the analysis sees it, so suggestions become reactions to stale snapshots.

This means the **CPU cost growth as chunk size increases is the price you pay for accurate, consistent data**, not a bug or inefficiency to optimize away. The right framing of the chunk-size question is:

> What is the **largest** chunk size whose per-call cost still fits comfortably inside one tick's budget?

— not "what's cheapest?". The default of 400 reflects this tradeoff.

### Per-bot cost is more meaningful than total CPU

Comparing total mod-time across chunk sizes is misleading because larger chunks finish scans faster and therefore run more analysis cycles in the same wall-clock window. To compare apples to apples, divide by the number of items processed:

- `background-refresh` at `chunk_size=400`: ~0.44 ms / 400 bots = **~1.1 µs per bot**
- `background-refresh` at `chunk_size=10`:  ~0.12 ms /  10 bots = **~12 µs per bot**

So `chunk_size=400` is roughly **10× more efficient per bot** than `chunk_size=10`. The reason it shows higher *total* CPU in the benchmark is that it's getting more useful work done in the same wall-clock window. Always normalize by units of work, not by ticks.

### When chunk size becomes a hard problem

For networks larger than the chunk size, the staleness/accuracy problem reappears even at the default. A 5000-bot network at `chunk_size=400` still takes 13 chunks × 5 ticks = ~65 ticks to fully scan. Megabase users have no good options: they can't get fresh and consistent data at the same time. The real optimization opportunity is **lowering per-item cost in the inner loops** of [scripts/bot-counter.lua](../scripts/bot-counter.lua), [scripts/logistic-cell-counter.lua](../scripts/logistic-cell-counter.lua), [scripts/undersupply.lua](../scripts/undersupply.lua), and [scripts/suggestions-calc.lua](../scripts/suggestions-calc.lua), so chunk size can be raised without breaking the per-tick frame budget.

## Adding configurations

### PowerShell

Each entry in `$Configurations` is a hashtable. The `label` field is used in the CSV. Every other field maps to an accessor name on `global_data` and a value the accessor should return:

```powershell
@{ label = "fast-bg"; chunk_size = 800; background_refresh_interval_ticks = 300 }
```

Boolean values (`$true`/`$false`) are converted to Lua `true`/`false`.

### Bash

Each entry in `CONFIGURATIONS` is a space-separated string of `key=value` pairs:

```bash
"label=fast-bg chunk_size=800 background_refresh_interval_ticks=300"
```

Use literal `true`/`false` for booleans (they map directly to Lua keywords).

### Generated Lua

Both harnesses emit the same Lua:

```lua
return function(global_data)
  global_data.chunk_size = function() return 800 end
  global_data.background_refresh_interval_ticks = function() return 300 end
end
```

See [scripts/global-data.lua](../scripts/global-data.lua) for the full list of accessors.

## Limitations

- **Runtime-global settings only.** Startup-stage settings (anything read in `data.lua`) cannot be overridden this way; they would require regenerating `mod-settings.dat`.
- **Aggregate timing only.** The harness parses Factorio's `--benchmark` summary lines (avg/min/max ms per update). For per-stage timing inside the mod, you'd need to add instrumentation.
- **Single mod scope.** Other mods' settings are not touched.

## One-off experiments

If you want to manually try a single configuration without the harness, copy `bench-overrides.lua.example` (in the mod root) to `bench-overrides.lua`, edit, and start Factorio normally. Delete the file when done.
