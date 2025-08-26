require("prototypes.sprite")
require("prototypes.shortcuts")
require("prototypes.custom-inputs")
local styles = data.raw["gui-style"].default

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
  padding = 4,
}

-- Both main and networks windows use a narrow frame
styles.li_window_style = {
  type = "frame_style",
  parent = "frame",
  padding = 4,
}

styles.li_mainwindow_content_style = {
  type = "table_style",
  parent = "slot_table",
  horizontal_spacing = 2,
  vertical_spacing = 2,
}


styles.fs_flib_titlebar_flow = {
  type = "horizontal_flow_style",
  horizontal_spacing = 8,
}

styles.fs_flib_titlebar_drag_handle = {
  type = "empty_widget_style",
  parent = "draggable_space",
  left_margin = 4,
  right_margin = 4,
  height = 24,
  horizontally_stretchable = "on",
}
