--- Loader for the benchmark profiler.
---
--- The real profiler lives in bench/bench-profiler.lua, which is a dev-only
--- directory left out of the release zip by package.ignore in info.json. In a
--- development checkout it is found and returned as-is, so the bench harness
--- and bench-overrides.lua keep requiring "scripts.bench-profiler". In a
--- shipped build the require fails and this stub stands in: never enabled,
--- and measure() just runs the function. The scheduler only calls the other
--- functions when the profiler is enabled.

local ok, real = pcall(require, "bench.bench-profiler")
if ok and type(real) == "table" then
  return real
end

local M = {}

M.enabled = false
M.task_interval_overrides = nil

--- @param name string Unused in the stub
--- @param fn function Zero-arg function to run
--- @return any Whatever fn() returns
function M.measure(name, fn)
  return fn()
end

return M
