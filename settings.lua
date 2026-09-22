-- Settings are shown by Factorio sorted on their order string. The per-player ones run 1..8; the
-- global ones fall in four groups: (a) what is gathered, (b) suggestions, (c) performance,
-- (d) behaviour. Names and descriptions are in locale/*/logistics-insights.cfg
data:extend(
  {
    -- Per-player settings: what each player sees
    {
      type = "bool-setting",
      name = "li-show-history",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "1"
    },
    {
      type = "bool-setting",
      name = "li-show-undersupply",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "2"
    },
    {
      type = "bool-setting",
      name = "li-show-suggestions",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3"
    },
    {
      type = "bool-setting",
      name = "li-show-networks-mini-window",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3.3"
    },
    {
      type = "bool-setting",
      name = "li-show-main-mini-window",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3.4"
    },
    {
      type = "int-setting",
      name = "li-max-items",
      setting_type = "runtime-per-user",
      default_value = 8,
      minimum_value = 7,
      maximum_value = 10,
      order = "4"
    },
    {
      type = "int-setting",
      name = "li-ui-update-interval",
      setting_type = "runtime-per-user",
      default_value = 60,
      minimum_value = 10,
      maximum_value = 120,
      order = "5.3"
    },
    {
      type = "int-setting",
      name = "li-highlight-duration",
      setting_type = "runtime-per-user",
      default_value = 10,
      minimum_value = 0,
      maximum_value = 1000,
      order = "7"
    },
    {
      type = "bool-setting",
      name = "li-show-trip-estimates",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "7.5"
    },
    {
      type = "double-setting",
      name = "li-initial-zoom",
      setting_type = "runtime-per-user",
      default_value = 0.3,
      minimum_value = 0.05,
      maximum_value = 10,
      order = "8"
    },

    -- (a) What is gathered
    {
      type = "bool-setting",
      name = "li-show-all-networks",
      setting_type = "runtime-global",
      default_value = true,
      order = "a-1"
    },
    {
      type = "bool-setting",
      name = "li-gather-quality-data-global",
      setting_type = "runtime-global",
      default_value = true,
      order = "a-2"
    },
    {
      type = "bool-setting",
      name = "li-calculate-undersupply",
      setting_type = "runtime-global",
      default_value = true,
      order = "a-3"
    },
    {
      type = "bool-setting",
      name = "li-ignore-player-demands-in-undersupply",
      setting_type = "runtime-global",
      default_value = true,
      order = "a-4"
    },

    -- (b) Suggestions
    {
      type = "int-setting",
      name = "li-age-out-suggestions-interval-minutes",
      setting_type = "runtime-global",
      default_value = 3,
      allowed_values = {0, 1, 3, 5, 10, 15, 30, 60},
      order = "b-1"
    },
    {
      type = "int-setting",
      name = "li-long-trip-min-distance",
      setting_type = "runtime-global",
      default_value = 200,
      minimum_value = 20,
      maximum_value = 10000,
      order = "b-2"
    },
    {
      type = "string-setting",
      name = "li-long-trip-suggestions",
      setting_type = "runtime-global",
      default_value = "normal",
      allowed_values = {"off", "relaxed", "normal", "sensitive"},
      order = "b-3"
    },
    {
      type = "bool-setting",
      name = "li-ignore-mobile-trips",
      setting_type = "runtime-global",
      default_value = true,
      order = "b-4"
    },

    -- (c) Performance
    {
      type = "int-setting",
      name = "li-chunk-size-global",
      setting_type = "runtime-global",
      default_value = 400,
      minimum_value = 10,
      maximum_value = 100000,
      order = "c-1"
    },
    {
      type = "int-setting",
      name = "li-chunk-processing-interval-ticks",
      setting_type = "runtime-global",
      default_value = 7,
      allowed_values = {3, 7, 13, 23, 37, 53},
      order = "c-2"
    },
    {
      type = "int-setting",
      name = "li-undersupply-rolling-divisor",
      setting_type = "runtime-global",
      default_value = 3,
      allowed_values = {1, 2, 3, 4, 5, 8},
      order = "c-3"
    },
    {
      type = "int-setting",
      name = "li-analysis-chunk-divisor",
      setting_type = "runtime-global",
      default_value = 4,
      allowed_values = {1, 2, 4, 8},
      order = "c-4"
    },
    {
      type = "int-setting",
      name = "li-background-refresh-interval",
      setting_type = "runtime-global",
      default_value = 30,
      minimum_value = 0,
      maximum_value = 3600,
      order = "c-5"
    },

    -- (d) Behaviour
    {
      type = "bool-setting",
      name = "li-freeze-highlighting-bots",
      setting_type = "runtime-global",
      default_value = true,
      order = "d-1"
    },
  }
)
