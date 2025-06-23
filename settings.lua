data:extend(
    {
        {
            type = "bool-setting",
            name = "logistics-insights-show-bot-delivering",
            setting_type = "runtime-per-user",
            default_value = true,
            order = "1"
        },
        {
            type = "bool-setting",
            name = "logistics-insights-show-history",
            setting_type = "runtime-per-user",
            default_value = true,
            order = "2"
        },
        {
            type = "bool-setting",
            name = "logistics-insights-show-activity",
            setting_type = "runtime-per-user",
            default_value = true,
            order = "3"
        },
        {
            type = "int-setting",
            name = "logistics-insights-max-items",
            setting_type = "runtime-per-user",
            default_value = 8,
            minimum_value = 6,
            maximum_value = 10,
            order = "4"
        }
}

)