local mod_gui = require("mod-gui")

local FRAME_NAME = "production_tracker_frame"
local REFRESH_TICKS = 6
local RATE_WINDOW = 60  -- ticks; the rate is averaged over this window

-- Session-only per-player UI state (not saved; rebuilt on load).
local full_numbers = {}
local rate_unit = {}
local sort_mode = {}
local filter_text = {}
local rate_prev = {}  -- player -> { tick, totals }
local rate_now = {}   -- player -> { name -> items/second }

local function format_short(n)
  if n >= 1e9 then return string.format("%.2fG", n / 1e9) end
  if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
  return string.format("%d", n)
end

local function format_full(n)
  local s = string.format("%d", math.floor(n + 0.5))
  local k
  repeat
    s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
  until k == 0
  return s
end

local function format_total(player, n)
  if full_numbers[player.index] then
    return format_full(n)
  end
  return format_short(n)
end

local function format_rate(player, r_per_sec)
  local per_min = rate_unit[player.index] == "minute"
  local r = per_min and (r_per_sec * 60) or r_per_sec
  local unit = per_min and "/min" or "/s"
  local num
  if r >= 1e6 then num = string.format("%.2fM", r / 1e6)
  elseif r >= 1e3 then num = string.format("%.1fk", r / 1e3)
  else num = string.format("%.1f", r) end
  return num .. unit
end

local function get_rate(player, name)
  local rates = rate_now[player.index]
  return (rates and rates[name]) or 0
end

local function row_matches(player, name)
  local f = filter_text[player.index]
  if not f or f == "" then return true end
  return string.find(string.lower(name), f, 1, true) ~= nil
end

local function read_totals_and_rates(player)
  local stats = player.force.get_item_production_statistics(player.surface)
  local totals = {}
  for name, count in pairs(stats.input_counts) do  -- input_counts = produced
    totals[name] = count
  end

  local pi = player.index
  local prev = rate_prev[pi]
  local recomputed = false
  if not prev then
    rate_prev[pi] = {tick = game.tick, totals = totals}
  elseif (game.tick - prev.tick) >= RATE_WINDOW then
    local dt = (game.tick - prev.tick) / 60.0
    local rates = {}
    for name, count in pairs(totals) do
      rates[name] = (count - (prev.totals[name] or 0)) / dt
    end
    rate_now[pi] = rates
    rate_prev[pi] = {tick = game.tick, totals = totals}
    recomputed = true
  end
  return totals, recomputed
end

local function add_row(grid, player, name, count)
  local visible = row_matches(player, name)
  local icon = grid.add{type = "label", name = "icon-" .. name, caption = "[item=" .. name .. "]"}
  icon.visible = visible
  local total = grid.add{type = "label", name = "total-" .. name, caption = format_total(player, count)}
  total.style.minimal_width = 80
  total.visible = visible
  local rate = grid.add{type = "label", name = "rate-" .. name, caption = format_rate(player, get_rate(player, name))}
  rate.style.minimal_width = 70
  rate.visible = visible
end

-- Sorted rebuild; clears and re-adds rows, so it resets scroll.
local function populate_sorted(player, totals)
  local frame = player.gui.screen[FRAME_NAME]
  local grid = frame and frame.list and frame.list.grid
  if not grid then return end
  local rates = rate_now[player.index] or {}

  local rows = {}
  for name, count in pairs(totals) do
    rows[#rows + 1] = {name = name, count = count, rate = rates[name] or 0}
  end
  if sort_mode[player.index] == "rate" then
    table.sort(rows, function(a, b) return a.rate > b.rate end)
  else
    table.sort(rows, function(a, b) return a.count > b.count end)
  end

  grid.clear()
  for _, r in ipairs(rows) do
    add_row(grid, player, r.name, r.count)
  end
  frame.list.empty.visible = (#rows == 0)
end

local function rebuild_sorted(player)
  populate_sorted(player, read_totals_and_rates(player))
end

-- In-place caption update; keeps scroll position. New items are appended.
-- In rate mode, re-rank when the rate refreshes (once per RATE_WINDOW).
local function refresh_live(player)
  local frame = player.gui.screen[FRAME_NAME]
  if not (frame and frame.visible and frame.list and frame.list.grid) then return end
  local totals, recomputed = read_totals_and_rates(player)
  local grid = frame.list.grid

  if sort_mode[player.index] == "rate" and recomputed then
    populate_sorted(player, totals)
    return
  end

  local any = false
  for name, count in pairs(totals) do
    any = true
    local total = grid["total-" .. name]
    if total then
      total.caption = format_total(player, count)
      grid["rate-" .. name].caption = format_rate(player, get_rate(player, name))
    else
      add_row(grid, player, name, count)
    end
  end
  if any then frame.list.empty.visible = false end
end

local function apply_filter(player)
  local frame = player.gui.screen[FRAME_NAME]
  local grid = frame and frame.list and frame.list.grid
  if not grid then return end
  for _, cell in pairs(grid.children) do
    local item = cell.name:match("^icon%-(.+)$")
      or cell.name:match("^total%-(.+)$")
      or cell.name:match("^rate%-(.+)$")
    if item then
      cell.visible = row_matches(player, item)
    end
  end
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
  local title = titlebar.add{type = "label", caption = "Production Tracker", style = "frame_title"}
  title.ignored_by_interaction = true
  local drag = titlebar.add{type = "empty-widget", style = "draggable_space_header"}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  titlebar.add{
    type = "sprite-button",
    name = "production_tracker_close",
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = "Close (reopen with the Production button, top-left)",
  }

  local controls = frame.add{type = "flow", name = "controls", direction = "horizontal"}
  controls.style.vertical_align = "center"
  controls.add{
    type = "checkbox",
    name = "production_tracker_full",
    state = full_numbers[player.index] or false,
    caption = "Full numbers",
  }
  controls.add{
    type = "switch",
    name = "production_tracker_rate_unit",
    left_label_caption = "/s",
    right_label_caption = "/min",
    switch_state = (rate_unit[player.index] == "minute") and "right" or "left",
    allow_none_state = false,
  }
  controls.add{
    type = "drop-down",
    name = "production_tracker_sort",
    items = {"Most created", "Highest rate"},
    selected_index = (sort_mode[player.index] == "rate") and 2 or 1,
  }

  local search = frame.add{type = "flow", name = "search", direction = "horizontal"}
  search.style.vertical_align = "center"
  search.add{type = "label", caption = "Filter:"}
  local box = search.add{type = "textfield", name = "production_tracker_search", text = filter_text[player.index] or ""}
  box.style.horizontally_stretchable = true

  local list = frame.add{type = "scroll-pane", name = "list", direction = "vertical"}
  list.style.maximal_height = 400
  list.add{type = "label", name = "empty", caption = "Nothing produced yet."}
  local grid = list.add{type = "table", name = "grid", column_count = 3}
  grid.style.horizontal_spacing = 12

  local button_flow = mod_gui.get_button_flow(player)
  if not button_flow.production_tracker_toggle then
    button_flow.add{
      type = "button",
      name = "production_tracker_toggle",
      caption = "Production",
      style = mod_gui.button_style,
      tooltip = "Toggle Production Tracker",
    }
  end

  rebuild_sorted(player)
end

local function build_for_all()
  for _, player in pairs(game.players) do
    build_gui(player)
  end
end

script.on_init(build_for_all)
script.on_configuration_changed(build_for_all)
script.on_event(defines.events.on_player_created, function(e)
  build_gui(game.get_player(e.player_index))
end)
script.on_event(defines.events.on_player_joined_game, function(e)
  build_gui(game.get_player(e.player_index))
end)

script.on_nth_tick(REFRESH_TICKS, function()
  for _, player in pairs(game.connected_players) do
    refresh_live(player)
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "production_tracker_full" then return end
  local player = game.get_player(e.player_index)
  full_numbers[player.index] = element.state
  refresh_live(player)
end)

script.on_event(defines.events.on_gui_switch_state_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "production_tracker_rate_unit" then return end
  local player = game.get_player(e.player_index)
  rate_unit[player.index] = (element.switch_state == "right") and "minute" or "second"
  refresh_live(player)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "production_tracker_sort" then return end
  local player = game.get_player(e.player_index)
  sort_mode[player.index] = (element.selected_index == 2) and "rate" or "total"
  rebuild_sorted(player)
end)

script.on_event(defines.events.on_gui_text_changed, function(e)
  local element = e.element
  if not (element and element.valid) or element.name ~= "production_tracker_search" then return end
  local player = game.get_player(e.player_index)
  filter_text[player.index] = string.lower(element.text)
  apply_filter(player)
end)

script.on_event(defines.events.on_gui_click, function(e)
  local element = e.element
  if not (element and element.valid) then return end
  local name = element.name
  if name ~= "production_tracker_close" and name ~= "production_tracker_toggle" then return end
  local player = game.get_player(e.player_index)
  local frame = player.gui.screen[FRAME_NAME]
  if not frame then return end
  if name == "production_tracker_close" then
    frame.visible = false
  else
    frame.visible = not frame.visible
    if frame.visible then rebuild_sorted(player) end
  end
end)
