data:extend(
  {
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
    }
    ,
    {
      type = "double-setting",
      name = "li-initial-zoom",
      setting_type = "runtime-per-user",
      default_value = 0.3,
      minimum_value = 0.05,
      maximum_value = 10,
      order = "8",
    }, 
    {
      type = "bool-setting",
      name = "li-show-all-networks",
      setting_type = "runtime-global",
      default_value = true,
      order = "1"
    },
    {
      type = "bool-setting",
      name = "li-gather-quality-data-global",
      setting_type = "runtime-global",
      default_value = true,
      order = "2"
    },
    {
      type = "bool-setting",
      name = "li-calculate-undersupply",
      setting_type = "runtime-global",
      default_value = true,
      order = "2.2"
    },
    {
      type = "bool-setting",
      name = "li-freeze-highlighting-bots",
      setting_type = "runtime-global",
      default_value = true,
      order = "2.5"
    },
    {
      type = "bool-setting",
      name = "li-ignore-player-demands-in-undersupply",
      setting_type = "runtime-global",
      default_value = true,
      order = "2.8"
    },
    {
      type = "int-setting",
      name = "li-chunk-size-global",
      setting_type = "runtime-global",
      default_value = 400,
      minimum_value = 10,
      maximum_value = 100000,
      order = "3"
    }
    ,
    {
      type = "int-setting",
      name = "li-chunk-processing-interval-ticks",
      setting_type = "runtime-global",
      default_value = 3,
      allowed_values  = {3, 7, 13, 23, 37, 53},
      order = "4"
    }
    ,
    {
      type = "int-setting",
      name = "li-age-out-suggestions-interval-minutes",
      setting_type = "runtime-global",
      default_value = 3,
      allowed_values  = {0, 1, 3, 5, 10, 15, 30, 60},
      order = "4.5"
    }
    ,
    {
      type = "int-setting",
      name = "li-background-refresh-interval",
      setting_type = "runtime-global",
      default_value = 10,
      minimum_value = 0,
      maximum_value = 3600,
      order = "5"
    }
  }
)
