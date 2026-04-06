# Testing Logistics Insights

There are two test suites: **unit tests** (busted, runs outside Factorio) and **integration tests** (factorio-test, runs inside the Factorio engine).

## Unit Tests (busted)

Unit tests mock Factorio globals and test module logic in isolation. They run fast and don't need the game installed.

### Prerequisites

- Lua 5.1+ or LuaJIT
- [busted](https://lunarmodules.github.io/busted/) test framework

Install via LuaRocks:

```bash
luarocks install busted
```

### Running

From the mod root directory:

```bash
busted
```

Configuration is in `.busted`. Tests are in `tests/*_spec.lua` (excluding `tests/integration/`). The mock Factorio environment is set up automatically via `tests/mocks/factorio.lua`.

## Integration Tests (factorio-test)

Integration tests run inside the real Factorio engine via the [factorio-test](https://mods.factorio.com/mod/factorio-test) framework. They create actual logistics networks, let LI's scheduler run, and assert on the computed data.

### Prerequisites

- Factorio 2.0 (standalone install, not necessarily the Steam version)
- Node.js (for the factorio-test CLI)
- The `factorio-test` mod (from the Factorio mod portal)
- The `flib` mod (LI dependency, from the mod portal)

### Setup

1. **Install the CLI:**

   ```bash
   npm install
   ```

   This installs `factorio-test-cli` from `package.json`.

2. **Create `factorio-test.json`** in the mod root (gitignored, machine-specific):

   ```json
   {
     "modPath": ".",
     "factorioPath": "/path/to/factorio.app/Contents/MacOS/factorio",
     "test": {
       "game_speed": 1000,
       "default_timeout": 18000
     }
   }
   ```

   Replace `factorioPath` with the path to your Factorio binary:
   - macOS app bundle: `/path/to/factorio.app/Contents/MacOS/factorio`
   - macOS standalone: `/path/to/factorio/bin/x64/factorio`
   - Linux: `/path/to/factorio/bin/x64/factorio`
   - Windows: `C:\\path\\to\\Factorio\\bin\\x64\\factorio.exe`

3. **Set up the mods directory.** The CLI creates `factorio-test-data-dir/mods/` and symlinks your mod there automatically. You need to manually add `flib` and `factorio-test`:

   ```bash
   # Symlink flib from your Factorio mods directory
   ln -s "/path/to/factorio/mods/flib_VERSION.zip" ./factorio-test-data-dir/mods/

   # Symlink factorio-test (download from mods.factorio.com/mod/factorio-test first)
   ln -s "/path/to/factorio-test_VERSION.zip" ./factorio-test-data-dir/mods/
   ```

   The CLI auto-downloads these via `fmtk` but this can fail due to mod portal authentication issues. Symlinking from an existing Factorio install is the reliable approach.

4. **Fix `config.ini`** (if needed). The CLI generates `factorio-test-data-dir/config.ini`. On macOS, the `read-data` path may be wrong. It should point to your Factorio's data directory:

   ```ini
   [path]
   read-data=/path/to/factorio.app/Contents/data
   write-data=/path/to/mod/factorio-test-data-dir
   ```

### Running

```bash
# With graphics (interactive, useful for debugging)
npx factorio-test run --graphics

# Headless (CI-friendly)
npx factorio-test run

# Verbose output (shows log() calls from tests)
npx factorio-test run -v

# Run a specific test by name pattern
npx factorio-test run "smoke"
```

### Test structure

- `tests/integration/helpers.lua` - `NetworkBuilder` for creating logistics networks, utility functions
- `tests/integration/basic_network_spec.lua` - Scenario tests (network discovery, bot counts, analysis, settings variation)

Tests are registered in `control.lua` at the bottom, guarded by `script.active_mods["factorio-test"]`. To add a new test file, add its module path to the test list there.

### Writing new tests

Use the `NetworkBuilder` from `helpers.lua` to set up logistics networks, `after_ticks()` to wait for LI's pipeline to run, and `done()` to signal test completion:

```lua
test("my scenario", function()
  async(10000)
  local builder = NetworkBuilder.new(game.surfaces[1], {0, 0}, "player")
  builder:add_roboport({0, 0}, {bots = 10})
  builder:add_provider({5, 0}, {{"iron-plate", 100}})
  builder:build()

  helpers.teleport_player({0, 0})

  after_ticks(5200, function()
    local network = game.surfaces[1].find_logistic_network_by_position({0, 0}, "player")
    local nwd = storage.networks[network.network_id]
    -- assertions here
    done()
  end)
end)
```

Key timing: ~200 ticks for network discovery, ~5000 more for a full scan + analysis cycle.

## Gitignored files

These are generated/machine-specific and should not be committed:

- `node_modules/`, `package.json`, `package-lock.json` - npm artifacts
- `factorio-test.json` - machine-specific Factorio path
- `factorio-test-data-dir/` - CLI runtime data (config, mods, saves)
- `luacov.*` - coverage output
