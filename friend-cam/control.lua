local mod_gui = require("mod-gui")

local FRAME_NAME = "friend_cam_frame"
local ZOOM_MIN, ZOOM_MAX, ZOOM_FACTOR = 0.15, 3.0, 1.25

-- Per-viewer watch choice. Session-only (a plain table, not storage): it's set
-- from a GUI event and only drives a local camera, so it can't desync.
local watch_target = {}

local function watchable(viewer)
  local list = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= viewer.index then
      list[#list + 1] = p
    end
  end
  return list
end

-- Dropdown choice if still valid, else the first other player, else yourself
-- (so the window is never blank, which also makes solo play work).
local function resolve_target(viewer)
  local chosen_index = watch_target[viewer.index]
  if chosen_index then
    local p = game.get_player(chosen_index)
    if p and p.connected and p.index ~= viewer.index then
      return p
    end
  end
  return watchable(viewer)[1] or viewer
end

local function refresh_dropdown(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.controls and frame.controls.friend_cam_select) then
    return
  end
  local dd = frame.controls.friend_cam_select
  local stored = watch_target[player.index]
  local names, selected = {}, 0
  for i, p in ipairs(watchable(player)) do
    names[i] = p.name
    if p.index == stored then
      selected = i
    end
  end
  dd.items = names
  dd.selected_index = (selected > 0) and selected or (#names > 0 and 1 or 0)
end

local function build_gui(player)
  local screen = player.gui.screen
  if screen[FRAME_NAME] then
    screen[FRAME_NAME].destroy()
  end

  local frame = screen.add{type = "frame", name = FRAME_NAME, direction = "vertical"}
  frame.location = {x = 15, y = 15}

  local titlebar = frame.add{type = "flow", name = "titlebar", direction = "horizontal"}
  titlebar.drag_target = frame
  local title = titlebar.add{type = "label", caption = "Friend Cam", style = "frame_title"}
  title.ignored_by_interaction = true
  local drag = titlebar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  titlebar.add{
    type = "sprite-button",
    name = "friend_cam_close",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = "Close (reopen with the Cam button, top-left)",
  }

  local controls = frame.add{type = "flow", name = "controls", direction = "horizontal"}
  controls.style.vertical_align = "center"
  local dd = controls.add{type = "drop-down", name = "friend_cam_select"}
  dd.style.horizontally_stretchable = true
  local zoom_out = controls.add{type = "button", name = "friend_cam_zoom_out", caption = "-", tooltip = "Zoom out"}
  local zoom_in = controls.add{type = "button", name = "friend_cam_zoom_in", caption = "+", tooltip = "Zoom in"}
  for _, b in pairs{zoom_out, zoom_in} do
    b.style.width = 28
    b.style.padding = 0
  end

  local cam = frame.add{
    type = "camera",
    name = "cam",
    position = player.position,
    surface_index = player.surface.index,
    zoom = 0.6,
  }
  cam.style.width = 320
  cam.style.height = 220

  local button_flow = mod_gui.get_button_flow(player)
  if not button_flow.friend_cam_toggle then
    button_flow.add{
      type = "button",
      name = "friend_cam_toggle",
      caption = "Cam",
      style = mod_gui.button_style,
      tooltip = "Toggle Friend Cam",
    }
  end

  refresh_dropdown(player)
end

local function build_for_all()
  for _, player in pairs(game.players) do
    build_gui(player)
  end
end

local function refresh_all_dropdowns()
  for _, player in pairs(game.connected_players) do
    refresh_dropdown(player)
  end
end

script.on_init(build_for_all)
script.on_configuration_changed(build_for_all)

script.on_event(defines.events.on_player_created, function(e)
  build_gui(game.get_player(e.player_index))
end)
script.on_event(defines.events.on_player_joined_game, function(e)
  build_gui(game.get_player(e.player_index))
  refresh_all_dropdowns()
end)
script.on_event(defines.events.on_player_left_game, function()
  refresh_all_dropdowns()
end)

-- Resolve the pick by name so it survives the roster reordering.
script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "friend_cam_select" then
    return
  end
  local viewer = game.get_player(e.player_index)
  local item = element.selected_index > 0 and element.get_item(element.selected_index) or nil
  local chosen = item and game.get_player(item)
  if chosen then
    watch_target[viewer.index] = chosen.index
  end
end)

script.on_nth_tick(6, function()
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.screen[FRAME_NAME]
    if frame and frame.visible and frame.cam then
      local target = resolve_target(player)
      frame.cam.position = target.position
      frame.cam.surface_index = target.surface.index
    end
  end
end)

script.on_event(defines.events.on_gui_click, function(e)
  local element = e.element
  if not (element and element.valid) then return end
  local name = element.name
  if name ~= "friend_cam_close" and name ~= "friend_cam_toggle"
    and name ~= "friend_cam_zoom_in" and name ~= "friend_cam_zoom_out" then
    return
  end
  local frame = game.get_player(e.player_index).gui.screen[FRAME_NAME]
  if not frame then return end
  if name == "friend_cam_close" then
    frame.visible = false
  elseif name == "friend_cam_toggle" then
    frame.visible = not frame.visible
  elseif frame.cam then
    if name == "friend_cam_zoom_in" then
      frame.cam.zoom = math.min(ZOOM_MAX, frame.cam.zoom * ZOOM_FACTOR)
    else
      frame.cam.zoom = math.max(ZOOM_MIN, frame.cam.zoom / ZOOM_FACTOR)
    end
  end
end)
