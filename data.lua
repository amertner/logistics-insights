require("prototypes.sprite")
require("prototypes.shortcuts")
require("prototypes.custom-inputs")
local styles = data.raw["gui-style"].default

styles.botsgui_frame_style = {
  type = "frame_style",
  parent = "frame",
  maximal_height = 400,
  padding = 8,
  graphical_set = {
    type = "composition",
    filename = "__core__/graphics/gui.png",
    priority = "extra-high-no-scale",
    corner_size = { 3, 3 },
    position = { 0, 0 },
    opacity = 0.9     -- 0 is fully transparent, 1 is fully opaque
  }
}

styles.botsgui_controller_style = {
  type = "frame_style",
  parent = "frame",
  graphical_set = {
    base = {
      center = {
        position = { 0, 0 },
        size = 1,
        color = { r = 0, g = 0, b = 0, a = 0.3 } -- semi-transparent black background
      },
      top = { position = { 0, 0 }, size = 1, color = { r = 1, g = 1, b = 1, a = 0.5 } },
      bottom = { position = { 0, 0 }, size = 1, color = { r = 1, g = 1, b = 1, a = 0.5 } },
      left = { position = { 0, 0 }, size = 1, color = { r = 1, g = 1, b = 1, a = 0.5 } },
      right = { position = { 0, 0 }, size = 1, color = { r = 1, g = 1, b = 1, a = 0.5 } },
    }
  },
  -- Optional: adjust padding as needed
  padding = 4,
}

styles.li_mainwindow_content_style = {
  type = "table_style",
  parent = "slot_table",
  horizontal_spacing = 2,
  vertical_spacing = 4,
}
