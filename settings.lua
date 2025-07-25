data:extend(
  {
    {
      type = "bool-setting",
      name = "li-show-bot-delivering",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "1"
    },
    {
      type = "bool-setting",
      name = "li-show-history",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "2"
    },
    {
      type = "bool-setting",
      name = "li-show-activity",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3"
    },
    {
      type = "bool-setting",
      name = "li-pause-while-hidden",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3.5"
    },
    {
      type = "bool-setting",
      name = "li-show-mini-window",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "3.6"
    },
    {
      type = "int-setting",
      name = "li-max-items",
      setting_type = "runtime-per-user",
      default_value = 8,
      minimum_value = 6,
      maximum_value = 10,
      order = "4"
    },
    {
      type = "int-setting",
      name = "li-chunk-size",
      setting_type = "runtime-per-user",
      default_value = 400,
      minimum_value = 10,
      maximum_value = 100000,
      order = "5"
    }
    ,
    {
      type = "int-setting",
      name = "li-chunk-processing-interval",
      setting_type = "runtime-per-user",
      default_value = 10,
      minimum_value = 1,
      maximum_value = 120,
      order = "5.2"
    }
    ,
    {
      type = "int-setting",
      name = "li-ui-update-interval",
      setting_type = "runtime-per-user",
      default_value = 60,
      minimum_value = 10,
      maximum_value = 120,
      order = "5.3"
    }
    ,
    {
      type = "bool-setting",
      name = "li-pause-for-bots",
      setting_type = "runtime-per-user",
      default_value = true,
      order = "6"
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
    }, }
)
