local mod_gui = require("mod-gui")

local FRAME_NAME = "buddy_teleport_frame"

-- Other connected players, in roster order.
local function buddies(viewer)
  local list = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= viewer.index then
      list[#list + 1] = p
    end
  end
  return list
end

-- The chosen buddy if still connected, else the first other player, else nil.
-- The choice lives in `storage` (not a plain table) because it drives a real
-- teleport, which is game state: every peer must resolve the same target or
-- the game desyncs. Resolved by name so it survives roster reordering.
local function resolve_buddy(viewer)
  local chosen = storage.buddy_choice[viewer.index]
  if chosen then
    local p = game.get_player(chosen)
    if p and p.connected and p.index ~= viewer.index then
      return p
    end
  end
  return buddies(viewer)[1]
end

local function refresh_dropdown(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.controls and frame.controls.buddy_teleport_select) then
    return
  end
  local dd = frame.controls.buddy_teleport_select
  local stored = storage.buddy_choice[player.index]
  local names, selected = {}, 0
  for i, p in ipairs(buddies(player)) do
    names[i] = p.name
    if p.name == stored then
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
  frame.location = {x = 15, y = 120}

  local titlebar = frame.add{type = "flow", name = "titlebar", direction = "horizontal"}
  titlebar.drag_target = frame
  local title = titlebar.add{type = "label", caption = "Buddy Teleport", style = "frame_title"}
  title.ignored_by_interaction = true
  local drag = titlebar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  titlebar.add{
    type = "sprite-button",
    name = "buddy_teleport_close",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = "Close (reopen with the Buddy TP button, top-left)",
  }

  local controls = frame.add{type = "flow", name = "controls", direction = "horizontal"}
  controls.style.vertical_align = "center"
  controls.add{type = "label", caption = "Buddy:"}
  local dd = controls.add{type = "drop-down", name = "buddy_teleport_select"}
  dd.style.minimal_width = 140

  local hint = frame.add{
    type = "label",
    caption = "Press your Teleport-to-buddy hotkey (default Ctrl+T) to jump to their view. Press it again to return to where you were.",
  }
  hint.style.single_line = false
  hint.style.maximal_width = 220

  local button_flow = mod_gui.get_button_flow(player)
  if not button_flow.buddy_teleport_toggle then
    button_flow.add{
      type = "button",
      name = "buddy_teleport_toggle",
      caption = "Buddy TP",
      style = mod_gui.button_style,
      tooltip = "Toggle Buddy Teleport panel",
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

-- A non-colliding spot for a character near `center` on `surface`, falling back
-- to the raw center if the surface is packed solid.
local function landing_spot(surface, center)
  return surface.find_non_colliding_position("character", center, 30, 0.5) or center
end

-- Jump to the buddy's VIEW location: `position`/`surface` follow the buddy's
-- remote view (where they're looking), while `physical_position` would be their
-- character. We want the camera, so we use `position`/`surface`. On success we
-- remember the viewer's own physical spot so the next press returns them there.
local function go_to_buddy(viewer)
  local buddy = resolve_buddy(viewer)
  if not buddy then
    viewer.print("Buddy Teleport: no other player to teleport to.")
    return
  end
  local from_position = viewer.physical_position
  local from_surface = viewer.physical_surface
  local surface = buddy.surface
  if viewer.teleport(landing_spot(surface, buddy.position), surface) then
    storage.return_point[viewer.index] = {
      position = from_position,
      surface_index = from_surface.index,
    }
    viewer.print("Buddy Teleport: jumped to " .. buddy.name .. "'s view. Press again to return.")
  else
    viewer.print("Buddy Teleport: couldn't find room near " .. buddy.name .. ".")
  end
end

-- Return to the spot saved on the way out.
local function go_home(viewer, point)
  local surface = game.surfaces[point.surface_index]
  if not (surface and surface.valid) then
    storage.return_point[viewer.index] = nil
    viewer.print("Buddy Teleport: your saved spot is gone.")
    return
  end
  if viewer.teleport(landing_spot(surface, point.position), surface) then
    storage.return_point[viewer.index] = nil
    viewer.print("Buddy Teleport: returned to where you were.")
  else
    viewer.print("Buddy Teleport: couldn't find room at your saved spot.")
  end
end

-- Ctrl+T toggles: out to the buddy if home, back to the saved spot if away.
local function toggle_teleport(viewer)
  local point = storage.return_point[viewer.index]
  if point then
    go_home(viewer, point)
  else
    go_to_buddy(viewer)
  end
end

local function init_storage()
  storage.buddy_choice = storage.buddy_choice or {}
  storage.return_point = storage.return_point or {}
end

script.on_init(function()
  init_storage()
  build_for_all()
end)
script.on_configuration_changed(function()
  init_storage()
  build_for_all()
end)

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

-- Store the pick by name so it survives roster reordering and is consistent
-- across all peers (this event is delivered deterministically to every peer).
script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "buddy_teleport_select" then
    return
  end
  local item = element.selected_index > 0 and element.get_item(element.selected_index) or nil
  if item then
    storage.buddy_choice[e.player_index] = item
  end
end)

script.on_event("buddy-teleport", function(e)
  toggle_teleport(game.get_player(e.player_index))
end)

script.on_event(defines.events.on_gui_click, function(e)
  local element = e.element
  if not (element and element.valid) then return end
  local name = element.name
  if name ~= "buddy_teleport_close" and name ~= "buddy_teleport_toggle" then
    return
  end
  local frame = game.get_player(e.player_index).gui.screen[FRAME_NAME]
  if not frame then return end
  if name == "buddy_teleport_close" then
    frame.visible = false
  else
    frame.visible = not frame.visible
  end
end)
