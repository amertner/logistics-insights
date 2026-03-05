# Logistics Insights - Factorio Mod

Real-time analytics mod for Factorio 2.0 logistics bot networks. Monitors bot activity, identifies bottlenecks, and suggests improvements. Multiplayer-compatible.

## Dependencies

- **flib** >= 0.15.0 (Factorio Standard Library)
- **base** >= 2.0.55
- Optional: **space-age**, **FactorySearch** >= 1.12.0

## Project Structure

```
control.lua                     # Entry point: event handlers, scheduler registration
data.lua                        # Data stage: prototypes & GUI styles
settings.lua                    # Mod setting definitions
prototypes/                     # Sprites, shortcuts, custom inputs
locale/                         # Translations (10+ languages)
graphics/                       # Icons and sprites
scripts/
  ├── Core
  │   ├── global-data.lua       # Global settings cache (storage.global)
  │   ├── player-data.lua       # Per-player state (storage.players[idx])
  │   ├── network-data.lua      # Per-network state (storage.networks[id])
  │   ├── scheduler.lua         # Tick-based task scheduler
  │   ├── events.lua            # Custom event emitter
  │   └── game-state.lua        # Freeze/pause/step logic
  │
  ├── Data Processing
  │   ├── chunker.lua           # Generic chunked iteration (spread work across ticks)
  │   ├── bot-counter.lua       # Bot state counting + delivery tracking
  │   ├── logistic-cell-counter.lua  # Roboport/cell analysis
  │   ├── tick-counter.lua      # Time tracking utility
  │   └── cache.lua             # Caching utilities
  │
  ├── Analysis
  │   ├── scan-coordinator.lua       # Orchestrates bot/cell scanning
  │   ├── analysis-coordinator.lua   # Orchestrates suggestions + undersupply
  │   ├── undersupply.lua            # Demand vs supply mismatch detection
  │   ├── suggestions-calc.lua       # Suggestion generation logic
  │   ├── suggestions.lua            # Suggestion storage & aging
  │   └── result-location.lua        # Entity location tracking
  │
  ├── GUI - Main Window (mainwin/)
  │   ├── main_window.lua       # Main window coordinator
  │   ├── mini_button.lua       # Top-left mini buttons
  │   ├── activity_row.lua      # Bot states (delivering, charging, idle...)
  │   ├── delivery_row.lua      # Current deliveries
  │   ├── history_rows.lua      # Historical delivery stats
  │   ├── network_row.lua       # Network info + quality
  │   ├── undersupply_row.lua   # Undersupplied items
  │   ├── suggestions_row.lua   # Improvement suggestions
  │   ├── sorted_item_row.lua   # Generic sorted item display
  │   ├── progress_bars.lua     # Scan progress indicators
  │   └── find_and_highlight.lua # Map highlighting on click
  │
  ├── GUI - Networks Window (networkswin/)
  │   ├── networks_window.lua   # Multi-network overview table
  │   ├── network_settings.lua  # Per-network settings panel
  │   └── exclusions_window.lua # Ignore-list management
  │
  └── Utilities
      ├── utils.lua             # Misc helpers
      ├── controller-gui.lua    # Mini window creation
      ├── tooltips-helper.lua   # Tooltip generation
      ├── migrations.lua        # Version upgrade handling
      ├── debugger.lua          # Debug logging
      └── json.lua              # JSON parsing
```

## Architecture

### Global State (`storage`)

```lua
storage = {
  global = { ... },                -- Cached global settings
  players = { [idx] = PlayerData },-- Per-player UI state & settings
  networks = { [id] = LINetworkData }, -- Per-network scan data & config
  fg_refreshing_network_id,        -- Foreground scan target
  bg_refreshing_network_id,        -- Background scan target
  analysing_networkdata,           -- Network being analyzed
  analysis_state = { ... },        -- Analysis pipeline progress
}
```

### Scheduler (`scheduler.lua`)

Tasks registered in `control.lua` with tick intervals. Two types:
- **Global tasks**: `fn()` — runs once per interval
- **Per-player tasks**: `fn(player, player_table)` — runs per player per interval

Tasks are spread across ticks to avoid lag spikes. Key tasks: `network-check` (29t), `bot/cell chunk` (7t), `background-refresh` (11t), `ui-update` (60t per player).

### Chunking (`chunker.lua`)

Large collections (bots, cells, requesters, storage) are processed in chunks across multiple ticks. Default chunk size: 400 (configurable 10–100k). Used by `bot-counter`, `logistic-cell-counter`, `undersupply`, and `suggestions-calc`.

### Scanning Pipeline

1. **Foreground scan** — Active player's network, high priority (every 7 ticks)
2. **Background scan** — Other networks, periodic (default 10s)
3. **Analysis** — After scan completes: free suggestions (O(1)), then chunked undersupply and storage analysis

### Event System (`events.lua`)

Custom events for UI coordination: `on_settings_pane_closed`, `on_forced_network_changed`, `on_ignorelist_changed`, `on_recreate_main_window`, `on_suggestions_changed`. Emitted via `events.emit(name, player_index)`.

## Key Patterns

- **Defensive validation**: Always check `.valid` on Factorio entities/GUI elements before use
- **Performance**: Local caching of stdlib functions, string key interning for item+quality combos, chunked processing
- **Quality-aware**: Factorio 2.0 quality system tracked separately for bots, roboports, items. Quality tables are `table<string, number>` (quality_name → count)
- **Multiplayer-safe**: Per-player windows/state, per-network shared data
- **Suggestion urgency**: "high" (red), "low" (yellow), "aging" (grey, resolved but still displayed for configured interval)

## Settings

**Per-player** (`runtime-per-user`): UI preferences (show/hide sections, max items, update interval, highlight duration, zoom level, mini window visibility)

**Global** (`runtime-global`): Performance tuning (chunk size, processing interval), feature toggles (quality data, undersupply calc, all networks), suggestion aging interval, background refresh interval

**Per-network** (stored in `LINetworkData`): Ignore lists for storage mismatches, undersupply items, buffer chests; quality mismatch settings

## GUI

Three windows:
1. **Main Window** — Activity, deliveries, history, undersupply, suggestions for current network
2. **Networks Window** — Table of all networks with summary stats
3. **Mini Window** — Two sprite buttons in top-left corner (network count + idle bots)

Interactive: click items to highlight on map, shift+click suggestions to ignore, ctrl+click to clear aging suggestions. Freeze/step buttons for detailed inspection.
