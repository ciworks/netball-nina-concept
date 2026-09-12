extends Node2D
## Finger-drag route movement prototype.
##
## Core interaction: touch the player, drag one continuous stroke, release.
## The freehand stroke is converted to an orthogonal grid route (no diagonals)
## via GestureInterpreter, previewed live, then committed into smooth automatic
## movement along the route. A 10x10 logical grid (0..10 coordinates) snaps
## every position. Test scenarios, reset, grid and debug toggles are exposed
## through the UI.
##
## The court renders in a 3/4 top-down isometric view: grid cells project to a
## diamond floor via _project_point(), and the tile floor plus painted markings
## are transformed with it, while the player token and ball stay upright in
## screen space at their projected positions.


const GRID_MAX := 10

const PAL_FLOOR := Color(0.96, 0.78, 0.45, 1.0)
const PAL_LINE := Color(1.0, 1.0, 1.0, 0.55)
const PAL_LINE_STRONG := Color(1.0, 1.0, 1.0, 0.85)
const PAL_BALL := Color(0.90, 0.36, 0.16, 1.0)
const PAL_ROUTE := Color(0.08, 0.78, 0.74, 0.85)
const PAL_CROSS := Color(1.0, 0.32, 0.28, 0.95)

## Isometric 3/4 projection: the logical x axis rotates 45 deg and the logical
## y component is halved, so a square grid renders as a classic diamond court.
const ISO_COS := 0.7071067811865476
const ISO_SIN := 0.3535533905932738
const ISO_ROT := 45.0

## Decorative trim texture (res://images/court_tile_edge.png). It is repeated
## along the court's front-right edge so the boundary reads as a lined edge.
const EDGE_STRIP_TEXTURE := preload("res://images/court_tile_edge.png")

const RATING_PERFECT_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const RATING_GREAT_COLOR := Color(0.32, 0.9, 0.52, 1.0)
const RATING_OK_COLOR := Color(1.0, 0.62, 0.25, 1.0)

const SCENARIOS := [
	{"name": "A - Horizontal", "player": Vector2i(2, 5), "target": Vector2i(8, 5)},
	{"name": "B - Vertical", "player": Vector2i(5, 8), "target": Vector2i(5, 2)},
	{"name": "C - L Shape", "player": Vector2i(3, 5), "target": Vector2i(10, 1)},
	{"name": "D - Reverse L", "player": Vector2i(8, 2), "target": Vector2i(2, 8)},
	{"name": "E - Multi-Segment", "player": Vector2i(3, 5), "target": Vector2i(5, 5)},
]

enum State { READY, DRAWING, COMMITTED, MOVING, COMPLETE, INVALID, MISS }

const GESTURE_SCRIPT := preload("res://scripts/gesture.gd")

@onready var player = $Player
@onready var ui: CanvasLayer = $UI
@onready var court_markings: TileMapLayer = $CourtRig/CourtMarkings
@onready var court_route: CourtBoard = $CourtRig/CourtRoute
@onready var court_rig: Node2D = $CourtRig

var court_rect := Rect2()
var cell_w := 1.0
var cell_h := 1.0

var player_cell := Vector2i(3, 5)
var target_cell := Vector2i(10, 1)
var _current_scenario := -1

var state: int = State.READY
var seconds_per_cell := 0.12

var gesture = GESTURE_SCRIPT.new()
var route: Array[Vector2i] = []
var committed_route: Array[Vector2i] = []
var _active_drag := -1
var _mouse_dragging := false
var _crossing := false
var _route_locked := false
var _locked_route: Array[Vector2i] = []

# Movement state.
var _move_pts: Array[Vector2] = []
var _move_cum: Array[float] = []
var _move_dist := 0.0
var _move_total := 0.0

var show_grid := false
var highlight_timer := 0.0
var _invalid_timer := 0.0
var _complete_timer := 0.0
var _miss_timer := 0.0
var _phase := 0.0
var _debug_accum := 0.0
var _successes := 0


func _ready() -> void:
	_recompute_layout()
	get_viewport().size_changed.connect(_on_viewport_resized)
	random_test()
	ui.bind({
		"reset": Callable(self, "random_test"),
		"scenario": Callable(self, "load_scenario"),
		"debug": Callable(self, "_on_debug_toggle"),
		"grid": Callable(self, "_on_grid_toggle"),
	})
	ui.set_debug_panel_visible(true)
	ui.set_status("READY")


func _process(delta: float) -> void:
	_phase += delta
	match state:
		State.INVALID:
			_invalid_timer -= delta
			if _invalid_timer <= 0.0:
				_enter_ready()
		State.COMPLETE:
			_complete_timer -= delta
			if _complete_timer <= 0.0:
				_advance_after_success()
		State.MISS:
			_miss_timer -= delta
			if _miss_timer <= 0.0:
				_advance_after_miss()
		State.MOVING:
			_advance_movement(delta)
	if highlight_timer > 0.0:
		highlight_timer -= delta
	_debug_accum -= delta
	if _debug_accum <= 0.0:
		_debug_accum = 0.15
		_push_debug()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if state == State.READY and _near_player(event.position):
				_begin_drag(event.index, event.position)
		else:
			if _active_drag == event.index and state == State.DRAWING:
				_end_drag()
	elif event is InputEventScreenDrag:
		if _active_drag == event.index and state == State.DRAWING:
			_update_drag(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if state == State.READY and _near_player(event.position):
					_mouse_dragging = true
					_begin_drag(-1, event.position)
			else:
				if _mouse_dragging:
					_mouse_dragging = false
					if state == State.DRAWING:
						_end_drag()
	elif event is InputEventMouseMotion:
		if _mouse_dragging and state == State.DRAWING:
			_update_drag(event.position)


func _begin_drag(index: int, pos: Vector2) -> void:
	_active_drag = index
	state = State.DRAWING
	_crossing = false
	_route_locked = false
	_locked_route.clear()
	player.set_pulse(false)
	gesture.begin(player_cell)
	gesture.push(screen_to_grid(pos))
	route = gesture.get_route()
	court_route.set_route(route)
	ui.set_status("DRAWING")
	ui.set_instruction("Draw toward the ball, then release.")
	queue_redraw()


func _update_drag(pos: Vector2) -> void:
	if _route_locked:
		return
	gesture.push(screen_to_grid(pos))
	route = gesture.get_route()
	if _route_self_intersects(route):
		if not _crossing:
			ui.set_instruction("Path crosses itself - release to restart.")
		_crossing = true
	elif _route_hits_cell(route, target_cell):
		_route_locked = true
		_locked_route = _clip_route_to_cell(route, target_cell)
		route = _locked_route
		ui.set_status("LOCKED")
		ui.set_instruction("Route locked - release to move.")
	court_route.set_route(route)
	queue_redraw()


func _end_drag() -> void:
	_active_drag = -1
	if _route_locked:
		route = _locked_route.duplicate()
	else:
		route = gesture.finish()
	if _route_cells(route) < 1:
		_enter_invalid()
		return
	if _route_self_intersects(route):
		_enter_invalid("Path can't cross itself - draw again without crossing back.")
		return
	_commit_route(route)


## True when the straight grid segments of `cells` pass through `cell`.
func _route_hits_cell(cells: Array[Vector2i], cell: Vector2i) -> bool:
	for i in range(1, cells.size()):
		var a := cells[i - 1]
		var b := cells[i]
		if (a.x == b.x and cell.x == a.x \
				and min(a.y, b.y) <= cell.y and cell.y <= max(a.y, b.y)) \
				or (a.y == b.y and cell.y == a.y \
				and min(a.x, b.x) <= cell.x and cell.x <= max(a.x, b.x)):
			return true
	return false


## Returns the route shortened so it ends exactly at `cell` (dropping any part
## of the stroke that went past the ball).
func _clip_route_to_cell(cells: Array[Vector2i], cell: Vector2i) -> Array[Vector2i]:
	for i in range(1, cells.size()):
		var a := cells[i - 1]
		var b := cells[i]
		if (a.x == b.x and cell.x == a.x \
				and min(a.y, b.y) <= cell.y and cell.y <= max(a.y, b.y)) \
				or (a.y == b.y and cell.y == a.y \
				and min(a.x, b.x) <= cell.x and cell.x <= max(a.x, b.x)):
			var clipped := cells.slice(0, i)
			clipped.append(cell)
			return clipped
	return cells.duplicate()


func _enter_invalid(message: String = "Try drawing a clearer path.") -> void:
	state = State.INVALID
	_invalid_timer = 1.1
	committed_route.clear()
	court_route.clear_route()
	ui.set_status("INVALID")
	ui.show_message(message, false)
	ui.set_instruction("Draw again from the player.")
	player.set_pulse(true)
	queue_redraw()


func _commit_route(cells: Array[Vector2i]) -> void:
	committed_route = cells.duplicate()
	court_route.set_route(committed_route)
	_move_pts.clear()
	_move_cum.clear()
	_move_cum.append(0.0)
	for i in cells.size():
		_move_pts.append(grid_to_screen(cells[i]))
	for i in range(1, cells.size()):
		_move_cum.append(_move_cum[i - 1] + float(_manhattan(cells[i - 1], cells[i])))
	_move_dist = 0.0
	_move_total = _move_cum[_move_cum.size() - 1]
	state = State.MOVING
	player.set_moving(true)
	ui.set_status("MOVING")
	ui.set_instruction("")
	if not cells.is_empty() and cells[cells.size() - 1] == target_cell:
		_show_route_rating(cells)
	queue_redraw()


## Rates a committed route that ends at the ball against the shortest possible
## route (straight Manhattan distance), then asks the UI to flash the verdict.
func _show_route_rating(cells: Array[Vector2i]) -> void:
	var actual := _route_cells(cells)
	var optimal := _manhattan(cells[0], target_cell)
	var extra := actual - optimal
	var word := "PERFECT"
	var col := RATING_PERFECT_COLOR
	if extra >= 4:
		word = "OK"
		col = RATING_OK_COLOR
	elif extra >= 1:
		word = "GREAT"
		col = RATING_GREAT_COLOR
	ui.flash_rating(word, col)


func _advance_movement(delta: float) -> void:
	var speed := 1.0 / seconds_per_cell
	_move_dist += speed * delta
	if _move_dist >= _move_total:
		_move_dist = _move_total
		player.position = _move_pts[_move_pts.size() - 1]
		_finish_movement()
		return
	var i := 0
	while i < _move_cum.size() - 2 and _move_cum[i + 1] <= _move_dist:
		i += 1
	var seg_len := _move_cum[i + 1] - _move_cum[i]
	var t := 0.0 if seg_len <= 0.0 else (_move_dist - _move_cum[i]) / seg_len
	player.position = _move_pts[i].lerp(_move_pts[i + 1], t)
	_update_player_cell_label()


func _update_player_cell_label() -> void:
	var c := _grid_cell_of_screen(player.position)
	if c != player_cell:
		player_cell = c
		player.set_label("Player (%d,%d)" % [c.x, c.y])


func _finish_movement() -> void:
	player.set_moving(false)
	player_cell = _grid_cell_of_screen(player.position)
	player.set_label("Player (%d,%d)" % [player_cell.x, player_cell.y])
	if player_cell == target_cell:
		state = State.COMPLETE
		_complete_timer = 1.8
		highlight_timer = 1.8
		_successes += 1
		ui.set_status("COMPLETE")
		ui.show_message("Target reached!", true)
		ui.set_instruction("Court cleared - loading the next court.")
	else:
		state = State.MISS
		_miss_timer = 1.2
		player.set_pulse(false)
		ui.set_status("MISS")
		ui.show_message("Missed the ball - next court loading.", false)
		ui.set_instruction("One chance per court.")
	queue_redraw()


func _enter_ready() -> void:
	state = State.READY
	player.set_pulse(true)
	ui.set_status("READY")
	_set_default_instruction()
	queue_redraw()


func _set_default_instruction() -> void:
	if _successes < 3:
		ui.set_instruction("Drag a path from the player to the ball.")
	else:
		ui.set_instruction("")


func random_test() -> void:
	_current_scenario = -1
	player_cell = _random_cell()
	var tries := 0
	while tries < 300:
		var t := _random_cell()
		if t != player_cell and _manhattan(player_cell, t) >= 5:
			target_cell = t
			break
		tries += 1
	_start_test("")


func load_scenario(index: int) -> void:
	if index < 0 or index >= SCENARIOS.size():
		return
	_current_scenario = index
	var s: Dictionary = SCENARIOS[index]
	player_cell = s["player"]
	target_cell = s["target"]
	_start_test("Scenario " + s["name"] + " loaded")


## After clearing a court the next layout is a random preset (A-E), never a
## retry of the same court.
func _advance_after_success() -> void:
	var idx := _random_scenario_index()
	if idx < 0:
		_enter_ready()
		return
	_current_scenario = idx
	var s: Dictionary = SCENARIOS[idx]
	player_cell = s["player"]
	target_cell = s["target"]
	_start_test("Court cleared! Next: " + s["name"])


## One attempt per court: after a missed move the next layout is a random
## preset (A-E), never a retry of the same court.
func _advance_after_miss() -> void:
	var idx := _random_scenario_index()
	if idx < 0:
		_enter_ready()
		return
	_current_scenario = idx
	var s: Dictionary = SCENARIOS[idx]
	player_cell = s["player"]
	target_cell = s["target"]
	_start_test("Next court: " + s["name"] + " - one chance to reach the ball.")


func _random_scenario_index() -> int:
	if SCENARIOS.is_empty():
		return -1
	var candidates: Array[int] = []
	for i in range(SCENARIOS.size()):
		if i != _current_scenario:
			candidates.append(i)
	if candidates.is_empty():
		return randi() % SCENARIOS.size()
	return candidates[randi() % candidates.size()]


func _start_test(announce: String) -> void:
	gesture.reset()
	route.clear()
	committed_route.clear()
	court_route.clear_route()
	_move_pts.clear()
	_move_cum.clear()
	_active_drag = -1
	_mouse_dragging = false
	_crossing = false
	highlight_timer = 0.0
	state = State.READY
	player.position = grid_to_screen(player_cell)
	player.radius = _token_radius()
	player.set_label("Player (%d,%d)" % [player_cell.x, player_cell.y])
	player.set_pulse(true)
	ui.set_status("READY")
	ui.set_debug_panel_visible(true)
	_set_default_instruction()
	if announce != "":
		ui.show_message(announce, true)
	queue_redraw()
	_push_debug()


func _on_debug_toggle(on: bool) -> void:
	ui.set_debug_panel_visible(on)


func _on_grid_toggle(on: bool) -> void:
	show_grid = on
	queue_redraw()


func _recompute_layout() -> void:
	var v: Vector2 = get_viewport_rect().size
	var margin := Vector2(40.0, 54.0)
	# The floor is an 11x11 panel grid (GRID_MAX+1 panels per side). The cell
	# size is chosen so the projected diamond (rotated 45 deg, y halved) fits
	# the available area: its footprint is 2*ISO_COS*span wide and
	# 2*ISO_SIN*span tall in cell units, where span = GRID_MAX + 1 panels.
	var avail := v - margin * 2.0
	var span := float(GRID_MAX + 1)
	var s := minf(
		avail.x / (2.0 * ISO_COS * span),
		avail.y / (2.0 * ISO_SIN * span)
	)
	cell_w = s
	cell_h = s
	# court_rect covers the GRID_MAX grid intervals. It is placed so its center
	# sits at the viewport center: the iso projection is symmetric about that
	# center, so the rendered diamond is centered in the viewport too.
	court_rect = Rect2(
		v * 0.5 - Vector2(cell_w, cell_h) * float(GRID_MAX) * 0.5,
		Vector2(cell_w * GRID_MAX, cell_h * GRID_MAX)
	)
	if player:
		player.radius = _token_radius()
		player.set_cell_height(cell_h)
		player.position = grid_to_screen(player_cell)
	if court_route:
		# The court floor is authored tile data now: the sand checkerboard on the
		# Court layer and the white line tiles on CourtMarkings, both under
		# CourtRig. Every layer shares one transform - CourtRig carries the
		# isometric flattening (scale before rotation in Godot node order) and
		# each layer carries the 45 deg diamond rotation plus the cell-size
		# scale - so the composition S*R matches the _project_point() iso
		# projection exactly and the layers stay registered with each other.
		var panel_origin := court_rect.position - Vector2(cell_w, cell_h) * 0.5
		court_rig.position = _project_point(panel_origin)
		court_rig.scale = Vector2(1.0, 0.5)
		for layer in court_rig.get_children():
			if layer is TileMapLayer:
				layer.rotation = deg_to_rad(ISO_ROT)
				layer.scale = Vector2(cell_w / 32.0, cell_h / 32.0)
		# A logical grid point sits at the CENTRE of floor panel (x, y), so the
		# marking layer is shifted half a cell back in logical space. Its panel
		# (x, y) then spans grid (x-1, y-1) .. (x, y), which is what makes the
		# painted third-line and mid-line tiles land exactly where the drawn
		# lines used to sit. The offset is specified in logical grid space and
		# rotated into the layer's parent frame.
		var mark_offset := Vector2(-cell_w, -cell_h) * 0.5
		court_markings.position = Vector2(
			ISO_COS * (mark_offset.x - mark_offset.y),
			ISO_COS * (mark_offset.x + mark_offset.y))
		court_route.layout(panel_origin, Vector2(cell_w, cell_h), GRID_MAX + 1)


func _on_viewport_resized() -> void:
	_recompute_layout()
	queue_redraw()


func _token_radius() -> float:
	return clampf(minf(cell_w, cell_h) * 0.24, 13.0, 28.0)


func grid_to_screen(cell: Vector2i) -> Vector2:
	var logical := court_rect.position + Vector2(cell.x * cell_w, cell.y * cell_h)
	return _project_point(logical)


func screen_to_grid(pos: Vector2) -> Vector2:
	var logical := _unproject_point(pos)
	return Vector2((logical.x - court_rect.position.x) / cell_w, (logical.y - court_rect.position.y) / cell_h)


## Projects a logical (pre-isometric) point into the 3/4 top-down diamond view.
func _project_point(p: Vector2) -> Vector2:
	var c := court_rect.get_center()
	var v := p - c
	return c + Vector2(ISO_COS * (v.x - v.y), ISO_SIN * (v.x + v.y))


## Inverse of _project_point: map a screen point back to logical grid coords.
func _unproject_point(p: Vector2) -> Vector2:
	var c := court_rect.get_center()
	var v := p - c
	var lx := (v.x / ISO_COS + v.y / ISO_SIN) * 0.5
	var ly := (v.y / ISO_SIN - v.x / ISO_COS) * 0.5
	return c + Vector2(lx, ly)


## Screen-space polyline for a logical circle lying on the court floor: the
## circle center and radius are in logical grid space, then projected so it
## renders as the correct isometric ellipse.
func _floor_ellipse(logical_center: Vector2, r: float, points: int = 36) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var a := TAU * float(i) / float(points)
		arr.append(_project_point(logical_center + Vector2(cos(a) * r, sin(a) * r)))
	return arr


func _grid_cell_of_screen(pos: Vector2) -> Vector2i:
	var g := screen_to_grid(pos)
	return Vector2i(clampi(roundi(g.x), 0, GRID_MAX), clampi(roundi(g.y), 0, GRID_MAX))


func _random_cell() -> Vector2i:
	return Vector2i(randi_range(0, GRID_MAX), randi_range(0, GRID_MAX))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(b.x - a.x) + absi(b.y - a.y)


func _route_cells(cells: Array[Vector2i]) -> int:
	var total := 0
	for i in range(1, cells.size()):
		total += _manhattan(cells[i - 1], cells[i])
	return total


## True when the route would make the player pass through any cell it already
## visited, i.e. crossing or doubling back over its own path to the ball.
func _route_self_intersects(cells: Array[Vector2i]) -> bool:
	var seen := {}
	if cells.is_empty():
		return false
	seen[cells[0]] = true
	for i in range(1, cells.size()):
		var a := cells[i - 1]
		var b := cells[i]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		if step == Vector2i.ZERO:
			continue
		var cur := a + step
		while true:
			if seen.has(cur):
				return true
			seen[cur] = true
			if cur == b:
				break
			cur += step
	return false


func _near_player(pos: Vector2) -> bool:
	var touch_radius := maxf(player.radius * 2.4, 30.0)
	return player.position.distance_to(pos) <= touch_radius


func _state_name() -> String:
	match state:
		State.READY: return "READY"
		State.DRAWING: return "DRAWING"
		State.COMMITTED: return "COMMITTED"
		State.MOVING: return "MOVING"
		State.COMPLETE: return "COMPLETE"
		State.INVALID: return "INVALID"
	return "READY"


func _push_debug() -> void:
	var cells: Array[Vector2i] = []
	if state == State.DRAWING:
		cells = route
	elif not committed_route.is_empty():
		cells = committed_route
	var dist := 0
	var segments := 0
	var extra := -1
	if cells.size() >= 2:
		dist = _route_cells(cells)
		segments = cells.size() - 1
		if cells[cells.size() - 1] == target_cell:
			extra = dist - _manhattan(cells[0], target_cell)
	else:
		dist = _manhattan(player_cell, target_cell)
	var route_str := "-"
	if cells.size() >= 1:
		var parts := PackedStringArray()
		for c in cells:
			parts.append("(%d,%d)" % [c.x, c.y])
		route_str = " -> ".join(parts)
	ui.set_debug({
		"player": "(%d,%d)" % [player_cell.x, player_cell.y],
		"target": "(%d,%d)" % [target_cell.x, target_cell.y],
		"route": route_str,
		"distance": dist,
		"time": float(dist) * seconds_per_cell,
		"state": _state_name(),
		"extra": extra,
		"segments": segments,
	})


func _draw() -> void:
	# Court floor: rendered by the Court TileMapLayer (z_index -1) behind this
	# node, so no solid floor rect is drawn here. The boundary diamond wraps the
	# full 11x11 panel area (court_rect grown by half a cell on every side),
	# projected into the isometric view.
	var o := court_rect.position - Vector2(cell_w, cell_h) * 0.5
	var ext := Vector2(cell_w * (GRID_MAX + 1), cell_h * (GRID_MAX + 1))
	var corners := PackedVector2Array([
		_project_point(o),
		_project_point(o + Vector2(ext.x, 0)),
		_project_point(o + ext),
		_project_point(o + Vector2(0, ext.y)),
		_project_point(o),
	])
	#_draw_court_edge_strip()
	draw_polyline(corners, PAL_LINE_STRONG, 5.0, true)
	_draw_court_markings()
	if show_grid:
		_draw_grid_overlay()
	_draw_ball()
	if state == State.DRAWING or state == State.MOVING or state == State.COMMITTED:
		_draw_route_overlay()
	if highlight_timer > 0.0:
		_draw_success_highlight()


## Lines the front-right court edge with EDGE_STRIP_TEXTURE: the strip is
## repeated along the projected lower-right diamond edge (front/bottom corner to
## right corner) so it reads as one continuous trim following the court
## boundary. Each repeat keeps the texture's own aspect, scaled so the strip
## thickness stays proportional to the cell size, and the repeat count is chosen
## so the strip ends exactly on the right corner.
func _draw_court_edge_strip() -> void:
	var o := court_rect.position - Vector2(cell_w, cell_h) * 0.5
	var ext := Vector2(cell_w * (GRID_MAX + 1), cell_h * (GRID_MAX + 1))
	var edge_a := _project_point(o + ext)                    # front (bottom) corner
	var edge_b := _project_point(o + Vector2(ext.x, 0.0))    # right corner
	var span := edge_b - edge_a
	var tex_size := EDGE_STRIP_TEXTURE.get_size()
	if span.length() < 1.0 or tex_size.x < 1.0 or tex_size.y < 1.0:
		return
	# Scale the strip so its height covers a fixed fraction of a cell.
	var k := maxf(minf(cell_w, cell_h) * 0.30, 6.0) / tex_size.y
	var count := maxi(int(round(span.length() / (tex_size.x * k))), 1)
	var tile_w := span.length() / k / float(count)
	draw_set_transform(edge_a, span.angle(), Vector2(k, k))
	for i in count:
		draw_texture_rect(
			EDGE_STRIP_TEXTURE,
			Rect2(Vector2(float(i) * tile_w, -tex_size.y * 0.5), Vector2(tile_w, tex_size.y)),
			false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_court_markings() -> void:
	# The third lines and the mid line are painted tiles on the CourtMarkings
	# layer now, so drawing them here too would double them up. Only the centre
	# ring is still drawn: it is not part of the tile atlas. The ring center is
	# projected so it lies on the diamond court and reads as an ellipse.
	var mid_logical := court_rect.position + court_rect.size * 0.5
	var center_r := maxf(cell_w, cell_h) * 1.2
	draw_polyline(_floor_ellipse(mid_logical, center_r), PAL_LINE, 3.0, true)


func _draw_grid_overlay() -> void:
	var font := ThemeDB.fallback_font
	for x in range(0, GRID_MAX + 1):
		var ax := court_rect.position.x + x * cell_w
		draw_line(
			_project_point(Vector2(ax, court_rect.position.y)),
			_project_point(Vector2(ax, court_rect.position.y + court_rect.size.y)),
			Color(1, 1, 1, 0.22), 1.0, true)
		if x < GRID_MAX:
			draw_string(font, _project_point(Vector2(ax + 3, court_rect.position.y + 12)), str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
	for y in range(0, GRID_MAX + 1):
		var ay := court_rect.position.y + y * cell_h
		draw_line(
			_project_point(Vector2(court_rect.position.x, ay)),
			_project_point(Vector2(court_rect.position.x + court_rect.size.x, ay)),
			Color(1, 1, 1, 0.22), 1.0, true)
		if y < GRID_MAX:
			draw_string(font, _project_point(Vector2(court_rect.position.x + 4, ay + 24)), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))


func _draw_ball() -> void:
	var p := grid_to_screen(target_cell)
	var ball_r: float = player.radius * 1.18
	var target_logical := court_rect.position + Vector2(target_cell.x * cell_w, target_cell.y * cell_h)
	# Pulsing target guidance ring painted on the floor (an ellipse in iso).
	var ring_r: float = ball_r + 8.0 + sin(_phase * 4.0) * 3.0
	draw_polyline(_floor_ellipse(target_logical, ring_r), Color(1, 1, 1, 0.6), 2.5, true)
	# Soft floor shadow under the ball.
	draw_colored_polygon(_floor_ellipse(target_logical, ball_r * 0.95), Color(0, 0, 0, 0.12))
	# The ball itself stays an upright sphere at its projected position.
	draw_circle(p, ball_r, PAL_BALL)
	# Netball-ish seams and gloss.
	draw_arc(p, ball_r * 0.82, -1.2, 3.3, 16, Color(1, 1, 1, 0.5), 2.0, true)
	draw_arc(p, ball_r * 0.82, 1.9, 6.4, 16, Color(1, 1, 1, 0.5), 2.0, true)
	draw_circle(p + Vector2(-ball_r * 0.32, -ball_r * 0.38), ball_r * 0.2, Color(1, 1, 1, 0.55))


func _draw_route_overlay() -> void:
	var pts: Array[Vector2] = []
	if state == State.DRAWING:
		for c in route:
			pts.append(grid_to_screen(c))
	else:
		# Committed/moving: show the remaining route from the player.
		pts.append(player.position)
		var next_i := 1
		while next_i < _move_cum.size() and _move_cum[next_i] <= _move_dist:
			next_i += 1
		for i in range(next_i, _move_pts.size()):
			pts.append(_move_pts[i])
	if pts.size() < 2:
		return
	var packed := PackedVector2Array(pts)
	draw_polyline(packed, Color(1, 1, 1, 0.55), 9.0, true)
	var route_col: Color = PAL_CROSS if (_crossing and state == State.DRAWING) else PAL_ROUTE
	draw_polyline(packed, route_col, 4.5, true)
	# Direction arrows midway through each segment.
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var dirv := b - a
		if dirv.length() < 0.01:
			continue
		var norm := dirv.normalized()
		var perp := Vector2(-norm.y, norm.x)
		var mid := a.lerp(b, 0.5)
		var tri := PackedVector2Array([
			mid + norm * 11.0,
			mid - norm * 7.0 + perp * 7.0,
			mid - norm * 7.0 - perp * 7.0,
		])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.9))
	# Endpoint marker.
	var endp := pts[pts.size() - 1]
	draw_circle(endp, 9.0, Color(1, 1, 1, 0.95))
	draw_arc(endp, 9.0, 0.0, TAU, 20, route_col, 3.0, true)


func _draw_success_highlight() -> void:
	var glow := 0.5 + 0.5 * sin(_phase * 6.0)
	var col := Color(1.0, 0.85, 0.25, 0.5 + 0.4 * glow)
	# Success rings lie on the floor, so they render as ellipses in the iso view.
	var p_logical := court_rect.position + Vector2(player_cell.x * cell_w, player_cell.y * cell_h)
	draw_polyline(_floor_ellipse(p_logical, player.radius + 10.0 + glow * 5.0), col, 5.0, true)
	var t_logical := court_rect.position + Vector2(target_cell.x * cell_w, target_cell.y * cell_h)
	draw_polyline(_floor_ellipse(t_logical, player.radius * 1.18 + 10.0 + glow * 5.0), col, 5.0, true)
