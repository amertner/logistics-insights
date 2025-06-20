data:extend(
    {
        {
            type = "bool-setting",
            name = "bot-insight-show-bot-delivering",
            setting_type = "runtime-per-user",
            default_value = true,
            order = "1"
        },
        {
            type = "bool-setting",
            name = "bot-insight-show-history",
            setting_type = "runtime-per-user",
            default_value = true,
            order = "1"
        },
        {
            type = "int-setting",
            name = "bot-insight-max-items",
            setting_type = "runtime-per-user",
            default_value = 6,
            minimum_value = 6,
            maximum_value = 10,
            order = "4"
        }
}

)