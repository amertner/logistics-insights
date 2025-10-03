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
-- A tiny, dim label used to show progress information
styles.li_progress_label = {
  type = "label_style",
  font = "default-small",
  font_color = {r=0.5,g=0.5,b=0.5},
  top_padding = 0,
  bottom_padding = 0,
  right_padding = 0,
}

-- The style used for row titles in main
styles.li_row_label =
{
  type = "label_style",
  parent = "heading_2_label",
  top_padding = 4,
  bottom_padding = 0,
}

-- The vertical flow used for rows of data
styles.li_row_vflow = {
  type = "vertical_flow_style",
  vertical_spacing = 0,
  padding = 0,
}

styles.li_row_hflow = {
  type = "horizontal_flow_style",
  horizontal_spacing = 4,
  vertical_align = "center",
  padding = 0,
}

styles.li_close_settings_button = {
  type = "button_style",
  parent = "tool_button",
  invert_colors_of_picture_when_disabled = false
}