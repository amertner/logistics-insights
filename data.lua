local styles = data.raw["gui-style"].default

styles.botsgui_frame_style = {
    type = "frame_style",
    parent = "frame",
    maximal_height = 300,
    padding = 8,
    graphical_set = {
        type = "composition",
        filename = "__core__/graphics/gui.png",
        priority = "extra-high-no-scale",
        corner_size = {3, 3},
        position = {0, 0},
        opacity = 0.5 -- 0 is fully transparent, 1 is fully opaque
    }  }

