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
## The court renders in a 3/4 top-down view: the logical x axis (the court's
## long axis) runs left to right across the screen, the logical y axis (its
## width) runs down the screen squashed to half, and each row slides sideways as
## it comes nearer the camera. The court therefore reads as one wide band with
## horizontal side lines and slanted transverse lines, sized by COURT_FILL so it
## sits inside the viewport with room around it. Both side lines are drawn across
## the full width of the screen and only the right goal line is drawn, so the
## court reads as carrying on past the left edge of the view. Grid points project
## through _project_point(), and the tile floor plus painted markings are
## transformed with it, while the player token and ball stay upright in screen
## space at their projected positions.


const GRID_MAX := 10

const PAL_FLOOR := Color(0.96, 0.78, 0.45, 1.0)
const PAL_LINE := Color(1.0, 1.0, 1.0, 0.85)
const PAL_LINE_STRONG := Color(1.0, 1.0, 1.0, 0.85)
const PAL_BALL := Color(0.90, 0.36, 0.16, 1.0)
const PAL_ROUTE := Color(0.08, 0.78, 0.74, 0.85)
const PAL_CROSS := Color(1.0, 0.32, 0.28, 0.95)

## 3/4 court view. VIEW_SQUASH halves the logical y axis (the court's width), so
## the floor reads as a court seen from in front and above rather than as a flat
## plan. VIEW_SKEW slides each logical row sideways in proportion to how near the
## camera it is, which is what puts the slant on the court's transverse lines
## (the ends and the third lines) while its side lines stay horizontal.
const VIEW_SQUASH := 0.5
## Positive, so a row nearer the camera slides right: the far end of a transverse
## line (the court ends, the third lines, the mid line) sits to the left of its
## near end.
const VIEW_SKEW := 0.12
## How much of the space the view can use the court actually takes. Below 1.0 the
## court sits inside the viewport with room around it rather than touching the
## edges.
const COURT_FILL := 0.75

const RATING_PERFECT_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const RATING_GOOD_COLOR := Color(0.32, 0.9, 0.52, 1.0)
const RATING_OK_COLOR := Color(1.0, 0.62, 0.25, 1.0)

## How tall the netball post stands, measured in court cells the same way the
## token's CELL_FILL is, so the post keeps its height relative to the player at
## every viewport size. A netball post is roughly three metres to the player's
## one and a half, so it stands about twice as tall as the token art.
const POST_HEIGHT_CELLS := 2.0

## The cell the post stands on: the middle of the right goal line, which is the
## line a feed is out past (logical x > GRID_MAX) and where a shot will be aimed
## once shooting exists.
const POST_CELL := Vector2i(GRID_MAX, 5)

const SCENARIOS := [
	{"name": "A - Horizontal", "player": Vector2i(2, 5), "target": Vector2i(8, 5)},
	{"name": "B - Vertical", "player": Vector2i(5, 8), "target": Vector2i(5, 2)},
	{"name": "C - L Shape", "player": Vector2i(3, 5), "target": Vector2i(10, 1)},
	{"name": "D - Reverse L", "player": Vector2i(8, 2), "target": Vector2i(2, 8)},
	{"name": "E - Multi-Segment", "player": Vector2i(3, 5), "target": Vector2i(5, 5)},
]

enum State { READY, DRAWING, COMMITTED, MOVING, COMPLETE, INVALID, MISS }

const GESTURE_SCRIPT := preload("res://scripts/gesture.gd")
## The top-line coach that feeds the ball in. Main owns the round; coach.gd owns
## the throw sequence and the ball's visual path.
const COACH_SCRIPT := preload("res://scripts/coach.gd")

## Seconds the player has to reach a loose ball after a dropped feed.
const LOOSE_BALL_TIME := 6.0
## Instruction shown while the token holds the ball: what the shot power meter
## asks of the player.
const SHOT_HINT := "Hold to charge the shot power, release to set it."
## Seconds the route highlight and the rating beat hold after a clean catch. The
## round itself stays in COMPLETE for POSSESSION_TIME, because the token keeps
## the ball until the shot window closes.
const CATCH_COMPLETE_TIME := 1.6
## Seconds the token holds the ball after taking a feed: the window the shot
## power meter is up for. Letting it run out without a shot is a missed shot and
## the coach feeds the next ball, so every possession resolves even though
## shooting itself is not built yet.
const POSSESSION_TIME := 3.0

@onready var player = $Player
@onready var ui: CanvasLayer = $UI
@onready var court_markings: TileMapLayer = $CourtRig/CourtMarkings
@onready var court_route: CourtBoard = $CourtRig/CourtRoute
@onready var court_rig: Node2D = $CourtRig
@onready var goal_post: Sprite2D = $GoalPost

## Top-line coach feeding the ball. Built in code (see _create_coach) so the
## placeholder sprite needs no scene node and no texture file.
var coach: CoachThrower = null

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
## How long the token has stood on its current cell, in seconds. Reset every time
## the token changes cell, so it is the token's settling time - what the coach
## reads to tell a player who is set on the ball from one who has only just
## arrived, and therefore only has a coin flip at taking it.
var _cell_dwell := 0.0

var show_grid := false
var highlight_timer := 0.0
var _invalid_timer := 0.0
var _complete_timer := 0.0
var _miss_timer := 0.0
var _phase := 0.0
var _debug_accum := 0.0
var _successes := 0

# Coach feed state. _throw_pending holds a finished feed until the player is not
# mid-action; the outcome was already judged the moment the ball last touched
# down. _ball_out marks a feed that landed outside the court, which is a miss.
var _throw_pending := false
var _throw_caught := false
var _ball_out := false
var _ball_loose := false
## Cell a feed's ball came to rest on when it was not caught, which is where the
## loose-ball chase sends the player.
var _loose_cell := Vector2i.ZERO
var _loose_timer := 0.0
var _feed_count := 0

## True while the token is holding the ball: from a clean catch or a collected
## loose ball until the coach takes the ball back for the next feed. This is the
## window the shot power meter is shown in - the player only owns the ball then,
## and shooting does not exist yet, so nothing else reads it.
var _has_ball := false
## Last visibility pushed to the power gauge, so the UI is only told when it
## actually changes rather than every frame.
var _gauge_shown := false
## Last visibility pushed to the shot direction meter, which only appears once a
## power value has been selected.
var _direction_shown := false
## The shot power value the player last selected by holding the meter down and
## releasing, or -1.0 while nothing is selected. A shot will be judged on this
## once shooting exists; the direction that pairs with it is not built yet.
var _selected_power := -1.0


func _ready() -> void:
	_recompute_layout()
	_create_coach()
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
	# The token's settling clock. It is only reset when the token changes cell, so
	# the coach can tell a player who is set on the ball from one still arriving.
	_cell_dwell += delta
	match state:
		State.INVALID:
			_invalid_timer -= delta
			if _invalid_timer <= 0.0:
				_enter_ready()
		State.COMPLETE:
			_complete_timer -= delta
			if _complete_timer <= 0.0:
				if _has_ball:
					# The token still holds the ball, so this clock was not
					# waiting on the catch - it was holding the shot window open
					# and the shot never came.
					_shot_window_expired()
				else:
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
	# A dropped feed is only lost while the player is free to chase it: the
	# clock pauses during a drag or a walk, so a committed route always finishes.
	if _ball_loose and state == State.READY:
		_loose_timer -= delta
		if _loose_timer <= 0.0:
			_lose_loose_ball()
	_resolve_pending_throw()
	_sync_power_gauge()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Holding the ball turns a press into a power charge and its release into a
	# selection, so the meter is driven by the same press the drag uses. The two
	# can never overlap: a drag only starts in READY, and possession is COMPLETE.
	if event is InputEventScreenTouch:
		if event.pressed:
			if _has_ball:
				_begin_power_charge()
			elif state == State.READY and _near_player(event.position):
				_begin_drag(event.index, event.position)
		else:
			if _has_ball:
				_release_power_charge()
			elif _active_drag == event.index and state == State.DRAWING:
				_end_drag()
	elif event is InputEventScreenDrag:
		if _active_drag == event.index and state == State.DRAWING:
			_update_drag(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _has_ball:
					_begin_power_charge()
				elif state == State.READY and _near_player(event.position):
					_mouse_dragging = true
					_begin_drag(-1, event.position)
			else:
				if _has_ball:
					_release_power_charge()
				elif _mouse_dragging:
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
	# No rating here: drawing a route that happens to end on the ball is not a
	# result. The words are flashed by _complete_catch() instead, so PERFECT /
	# GOOD / OK only ever appears for a ball that was actually taken.
	queue_redraw()


## Rates the route the token actually walked against the shortest route to the
## cell it ended on (straight Manhattan distance), then asks the UI to flash the
## verdict. Called only from _complete_catch(), so the words never appear unless
## a catch was made.
func _show_route_rating(cells: Array[Vector2i]) -> void:
	if cells.size() < 2:
		return
	var actual := _route_cells(cells)
	var optimal := _manhattan(cells[0], cells[cells.size() - 1])
	var extra := actual - optimal
	var word := "PERFECT"
	var col := RATING_PERFECT_COLOR
	if extra >= 4:
		word = "OK"
		col = RATING_OK_COLOR
	elif extra >= 1:
		word = "GOOD"
		col = RATING_GOOD_COLOR
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
		# A new cell means the token is not settled there yet.
		_cell_dwell = 0.0
		player.set_label("Player (%d,%d)" % [c.x, c.y])


func _finish_movement() -> void:
	player.set_moving(false)
	player_cell = _grid_cell_of_screen(player.position)
	# The token has just stopped on this cell, so its settling clock restarts.
	_cell_dwell = 0.0
	player.set_label("Player (%d,%d)" % [player_cell.x, player_cell.y])
	# A feed that landed while the token was still walking is settled first: the
	# catch was already judged the instant the ball landed.
	if _throw_pending and _throw_caught:
		_complete_catch()
		return
	# Reaching the ball only collects it once the coach has let it go: the feed
	# cannot be completed while the ball is still in the coach's hands. Once the
	# feed is over the ball sits wherever it came to rest, so it is the ball's real
	# position - not the cell the throw was aimed at - that has to be reached.
	if player_cell == _collect_cell() and _ball_released() and not _feed_airborne():
		# The token is on the loose ball, so it now holds it: the shot power
		# meter is up for as long as this possession lasts.
		_has_ball = true
		state = State.COMPLETE
		_complete_timer = POSSESSION_TIME
		highlight_timer = 1.8
		_successes += 1
		ui.set_status("COMPLETE")
		ui.show_message("Ball collected!", true)
		ui.set_instruction(SHOT_HINT)
		queue_redraw()
		return
	# The feed has not been settled yet, so a walk that fell short is not the end
	# of the round: hand control straight back and let the ball decide.
	state = State.READY
	player.set_pulse(true)
	if _ball_loose:
		ui.set_phase_status("LOOSE BALL")
		ui.set_instruction("Ball is loose at (%d,%d) - drag onto it." % [target_cell.x, target_cell.y])
	elif _feed_airborne():
		ui.set_phase_status("FEED INCOMING")
		ui.set_instruction("Get onto (%d,%d) before the ball lands." % [target_cell.x, target_cell.y])
	elif _feed_held():
		# The coach still has the ball: the feed is on its way but nothing
		# completes yet, because the round is only decided when the ball lands.
		ui.set_phase_status("COACH FEED")
		if player_cell == target_cell:
			ui.set_instruction("Stay on (%d,%d) until the feed arrives." % [target_cell.x, target_cell.y])
		else:
			ui.set_instruction("Get onto (%d,%d) before the feed lands." % [target_cell.x, target_cell.y])
	else:
		ui.set_status("READY")
		_set_default_instruction()
	queue_redraw()


func _enter_ready() -> void:
	state = State.READY
	player.set_pulse(true)
	ui.set_status("READY")
	_set_default_instruction()
	# A feed may have landed while the last drag was being repaired.
	_resolve_pending_throw()
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
	_start_coach_round()
	queue_redraw()
	_push_debug()


func _on_debug_toggle(on: bool) -> void:
	ui.set_debug_panel_visible(on)


func _on_grid_toggle(on: bool) -> void:
	show_grid = on
	queue_redraw()


func _recompute_layout() -> void:
	var v: Vector2 = get_viewport_rect().size
	var margin := Vector2(16.0, 14.0)
	# The floor is an 11x11 panel grid (GRID_MAX+1 panels per side). This view
	# puts the grid's x axis across the screen and squashes its y axis to
	# VIEW_SQUASH, with VIEW_SKEW adding the row slide on top of the width; the
	# cell size is the largest that fits that band in the available area.
	var avail := v - margin * 2.0
	var span := float(GRID_MAX + 1)
	# The largest cell that fits the band, then scaled back by COURT_FILL so the
	# court keeps its shape but leaves room around itself in the viewport.
	var s := minf(
		avail.x / (span * (1.0 + VIEW_SKEW)),
		avail.y / (span * VIEW_SQUASH)
	) * COURT_FILL
	cell_w = s
	cell_h = s
	# court_rect covers the GRID_MAX grid intervals, centered on the viewport to
	# start with.
	court_rect = Rect2(
		v * 0.5 - Vector2(cell_w, cell_h) * float(GRID_MAX) * 0.5,
		Vector2(cell_w * GRID_MAX, cell_h * GRID_MAX)
	)
	# The skewed band is not centered on the logical rectangle, so nudge the
	# court until its projected outline (the whole panel area) IS centered -
	# otherwise the court sits off to one side of the viewport.
	court_rect.position += _view_unapply(v * 0.5 - _projected_panel_rect().get_center())
	if player:
		player.radius = _token_radius()
		player.set_cell_height(cell_h)
		player.position = grid_to_screen(player_cell)
	if court_route:
		# The court floor is authored tile data now: the sand checkerboard on the
		# Court layer and the white line tiles on CourtMarkings, both under
		# CourtRig. CourtRig carries the whole view as one matrix - logical x
		# straight across the screen, logical y squashed by VIEW_SQUASH and slid
		# sideways by VIEW_SKEW - and each layer carries only its atlas-to-cell
		# scale, so a tile lands exactly where _project_point() puts the same
		# logical point and the layers stay registered with each other.
		var panel_origin := court_rect.position - Vector2(cell_w, cell_h) * 0.5
		court_rig.transform = Transform2D(
			Vector2(1.0, 0.0),
			Vector2(VIEW_SKEW, VIEW_SQUASH),
			_project_point(panel_origin))
		for layer in court_rig.get_children():
			if layer is TileMapLayer:
				layer.rotation = 0.0
				layer.scale = Vector2(cell_w / 32.0, cell_h / 32.0)
		# A logical grid point sits at the CENTRE of floor panel (x, y), so the
		# marking layer is shifted half a cell back in logical space. Its panel
		# (x, y) then spans grid (x-1, y-1) .. (x, y), which is what makes the
		# painted third-line and mid-line tiles land exactly where the drawn
		# lines used to sit. The offset is a plain logical shift: the rig
		# already carries the view, so the child layers stay axis-aligned in
		# cell space.
		court_markings.position = Vector2(-cell_w, -cell_h) * 0.5
		court_route.layout(panel_origin, Vector2(cell_w, cell_h), GRID_MAX + 1)
	if coach != null:
		# The coach works in the same logical cell space as grid_to_screen(), so
		# its origin is court_rect.position (not the half-cell-back panel origin
		# the tile layers use) and a spot of (x, 0) lands on the top line.
		coach.layout(court_rect.position, Vector2(cell_w, cell_h), _project_point)
	if goal_post != null:
		# The post is a scene node, not generated art, and stays upright in screen
		# space the same way the token and the ball do - so only its scale follows
		# the court. Its base sits on its cell and its art is scaled so the whole
		# post is POST_HEIGHT_CELLS tall, which keeps it the same height next to
		# the player however the viewport resizes.
		goal_post.position = grid_to_screen(POST_CELL)
		var post_tex := goal_post.texture
		if post_tex != null and post_tex.get_height() > 0:
			var tex_h := float(post_tex.get_height())
			goal_post.scale = Vector2.ONE * (float(cell_h) * POST_HEIGHT_CELLS / tex_h)
			# A centered sprite is drawn around its origin, so lift the art by half
			# its height to sit its feet on the origin - i.e. on the goal line
			# rather than straddling it.
			goal_post.offset = Vector2(0.0, -tex_h * 0.5)


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


## The view's linear part: a logical offset becomes the screen offset it renders
## as - logical x across the screen, logical y squashed by VIEW_SQUASH and slid
## sideways by VIEW_SKEW.
func _view_apply(v: Vector2) -> Vector2:
	return Vector2(v.x + VIEW_SKEW * v.y, VIEW_SQUASH * v.y)


## Undoes the view's linear part, turning a screen-space offset back into the
## logical offset that renders as it.
func _view_unapply(v: Vector2) -> Vector2:
	var ly := v.y / VIEW_SQUASH
	return Vector2(v.x - VIEW_SKEW * ly, ly)


## Projects a logical (court-space) point into the 3/4 court view. Measured from
## the court center, so the view is anchored to the court itself rather than to
## the viewport: recentering the court moves it without changing its shape.
func _project_point(p: Vector2) -> Vector2:
	var c := court_rect.get_center()
	return c + _view_apply(p - c)


## Inverse of _project_point: map a screen point back to logical court coords.
func _unproject_point(p: Vector2) -> Vector2:
	var c := court_rect.get_center()
	return c + _view_unapply(p - c)


## Screen-space box around the projected outline of the whole panel area (the
## GRID_MAX+1 square of floor tiles). The skewed view leans that band sideways,
## so its outline is not centered on the logical rectangle; this is what the
## layout centers on the viewport instead.
func _projected_panel_rect() -> Rect2:
	var o := court_rect.position - Vector2(cell_w, cell_h) * 0.5
	var ext := Vector2(cell_w * (GRID_MAX + 1), cell_h * (GRID_MAX + 1))
	var p0 := _project_point(o)
	var p1 := _project_point(o + Vector2(ext.x, 0.0))
	var p2 := _project_point(o + ext)
	var p3 := _project_point(o + Vector2(0.0, ext.y))
	var mn := Vector2(minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y)))
	var mx := Vector2(maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y)))
	return Rect2(mn, mx - mn)


## Screen-space polyline for a logical circle lying on the court floor: the
## circle center and radius are in logical grid space, then projected so it
## renders as the correct flattened ellipse.
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
		"coach": _coach_debug_text(),
		"shot": _power_debug_text(),
	})


func _draw() -> void:
	# Court floor: rendered by the Court TileMapLayer (z_index -1) behind this
	# node, so no solid floor rect is drawn here. The lines below follow the
	# outer edge of the full 11x11 panel area (court_rect grown by half a cell on
	# every side), projected into the court view as a slanted band.
	var o := court_rect.position - Vector2(cell_w, cell_h) * 0.5
	var ext := Vector2(cell_w * (GRID_MAX + 1), cell_h * (GRID_MAX + 1))
	# The two long side lines run the whole width of the screen, so the court
	# reads as though it carries on past the viewport. Side lines are horizontal
	# in this view, so each one is a flat line at the projected y of its edge.
	var screen_w: float = get_viewport_rect().size.x
	var side_top: float = _project_point(o).y
	var side_bottom: float = _project_point(o + Vector2(0.0, ext.y)).y
	draw_line(Vector2(0.0, side_top), Vector2(screen_w, side_top), PAL_LINE_STRONG, 5.0, true)
	draw_line(Vector2(0.0, side_bottom), Vector2(screen_w, side_bottom), PAL_LINE_STRONG, 5.0, true)
	# Only the right goal line is drawn: the left end of the court is left open.
	draw_line(
		_project_point(o + Vector2(ext.x, 0.0)),
		_project_point(o + ext),
		PAL_LINE_STRONG, 5.0, true)
	#_draw_court_edge_strip()
	_draw_court_markings()
	if show_grid:
		_draw_grid_overlay()
	# While the coach holds or throws the ball it draws the ball itself, at its
	# own arc height, so the resting ball is only drawn when the coach is not
	# the one owning it.
	if coach == null or not (coach.ball_in_hand() or coach.ball_airborne()):
		_draw_ball()
	if coach != null and coach.indicator_visible():
		_draw_destination_indicator()
	if state == State.DRAWING or state == State.MOVING or state == State.COMMITTED:
		_draw_route_overlay()
	if highlight_timer > 0.0:
		_draw_success_highlight()


func _draw_court_markings() -> void:
	# The third lines and the mid line are painted tiles on the CourtMarkings
	# layer now, so drawing them here too would double them up. Only the centre
	# ring is still drawn: it is not part of the tile atlas. The ring center is
	# projected so it lies on the court floor and reads as a squashed ellipse.
	var mid_logical := court_rect.position + court_rect.size * 0.5
	var center_r := maxf(cell_w, cell_h) * 1.2
	draw_polyline(_floor_ellipse(mid_logical, center_r), PAL_LINE, 6.0, true)


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
	var ball_r: float = player.radius * 1.18
	# The guidance ring marks the cell the ball is actually on, whichever phase the
	# feed is in: while the coach holds it that is the throwing spot, and once it
	# is in play the ring follows the ball through its bounces, so the ring and the
	# ball never disagree about where the feed is.
	var ball_cell_now := _collect_cell()
	var target_logical := court_rect.position + Vector2(ball_cell_now.x * cell_w, ball_cell_now.y * cell_h)
	var ring_r: float = ball_r + 8.0 + sin(_phase * 4.0) * 3.0
	draw_polyline(_floor_ellipse(target_logical, ring_r), Color(1, 1, 1, 0.6), 2.5, true)
	# While the coach carries the ball, coach.gd draws it in the same node as the
	# hand holding it, so it is skipped here to avoid a double image.
	if coach != null and coach.round_active() and coach.ball_in_hand():
		return
	# Otherwise the ball is in play: coach.gd owns both its floor point and its
	# arc height, so what is drawn and what the catch is judged against can never
	# drift apart.
	var floor_logical := target_logical
	var p := grid_to_screen(target_cell)
	if coach != null and coach.round_active():
		floor_logical = coach.ball_floor_logical()
		p = coach.ball_screen()
		# A ball in the air reads as nearer the camera, so it grows a little.
		ball_r *= 1.0 + 0.22 * coach.air_height_ratio()
	# The shadow stays on the floor while the ball is above it.
	draw_colored_polygon(_floor_ellipse(floor_logical, ball_r * 0.95), Color(0, 0, 0, 0.12))
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


# --- Coach feed ---------------------------------------------------------------
# The coach runs its own sequence (spot pick, windup, release, flight) in coach.gd.
# This half of the round owns what the sequence means: which cell the ball must
# land on, whether that landing was a catch, and what a dropped feed leaves
# behind.


## The coach is built in code rather than authored in main.tscn: it is a
## placeholder block figure with no texture, and every position it needs is
## already computed by this script's projection helpers.
func _create_coach() -> void:
	coach = COACH_SCRIPT.new()
	coach.name = "Coach"
	add_child(coach)
	coach.layout(court_rect.position, Vector2(cell_w, cell_h), _project_point)
	coach.player_cell_provider = Callable(self, "_coach_judge_cell")
	coach.player_dwell_provider = Callable(self, "_player_dwell_seconds")
	coach.throw_resolved.connect(_on_throw_resolved)
	coach.ball_out_of_bounds.connect(_on_ball_out_of_bounds)


## What the coach reads to decide caught vs missed: the token's cell at that
## exact instant. The arc, the timings and the rendering never feed into this -
## the outcome comes from grid logic alone.
func _coach_judge_cell() -> Vector2i:
	return player_cell


## How long the token has been standing on its current cell, in seconds. The
## coach reads this to tell a player who is set on the landing spot from one who
## has only just arrived: a set player takes the ball cleanly, an arriving one
## only gets a roll of the dice and may see the ball come off them.
func _player_dwell_seconds() -> float:
	return _cell_dwell


## Starts one feed. The ball is thrown to the cell this round already marks as
## the target. Nothing about the feed is decided yet: the verdict is taken when
## the ball lands (see coach.gd), so a token that runs onto the cell during the
## hold or the flight can still make the catch.
func _start_coach_round() -> void:
	_throw_pending = false
	_throw_caught = false
	_ball_out = false
	_ball_loose = false
	_loose_timer = 0.0
	# The ball goes back to the coach for this feed, so the token no longer
	# holds it and the shot power meter has nothing to show until the next catch.
	_has_ball = false
	# A new feed means a new possession to come, so the value selected last time
	# is gone.
	_selected_power = -1.0
	_feed_count += 1
	if coach != null:
		coach.start_round(target_cell)
	ui.set_phase_status("COACH FEED")
	player.set_pulse(true)


func _on_throw_resolved(caught: bool, _destination: Vector2i) -> void:
	_throw_caught = caught
	_throw_pending = true


## The ball touched down outside the court, so the feed is dead. Deferred exactly
## like a landed feed, so a committed route always plays out before the reset.
func _on_ball_out_of_bounds(_cell: Vector2i) -> void:
	_ball_out = true
	_throw_pending = true


## Settles a landed feed once the player is not mid-action. The catch was already
## judged the moment the ball landed; this only chooses when to show it, so a
## feed that lands during a drag resolves as soon as the drag is over.
func _resolve_pending_throw() -> void:
	if not _throw_pending or state != State.READY:
		return
	if _ball_out:
		_feed_out_of_bounds()
	elif _throw_caught:
		_complete_catch()
	else:
		_begin_loose_ball()


func _feed_airborne() -> bool:
	return coach != null and coach.ball_airborne()


## True once the coach has let the ball go. Nothing completes before that: the
## round cannot be cleared while the feed is still in the coach's hands.
func _ball_released() -> bool:
	return coach == null or not coach.ball_in_hand()


## True while the coach still has the ball in hand, before the throw is made.
func _feed_held() -> bool:
	return coach != null and coach.ball_in_hand()


## The cell the ball actually occupies right now: while the coach holds it that is
## the throwing spot, and once it is in play it is wherever the physics has carried
## it. This is what has to be reached to collect the ball, so a feed that bounces
## away from the cell it was aimed at is collected where it really came to rest.
func _collect_cell() -> Vector2i:
	if coach != null:
		return coach.ball_cell()
	return target_cell


## The ball landed on the token: the feed was clean. This is the only place a
## route rating flashes, so PERFECT / GOOD / OK always means a ball was taken.
func _complete_catch() -> void:
	_throw_pending = false
	_ball_loose = false
	# The feed was taken, so the token holds the ball from here until the coach
	# takes it back: that possession is what the shot power meter is up for.
	_has_ball = true
	# Rate the route the token actually walked. A catch made without moving - the
	# token was already set on the spot waiting - has no route to judge, so nothing
	# flashes in that case.
	if committed_route.size() >= 2:
		_show_route_rating(committed_route)
	state = State.COMPLETE
	_complete_timer = POSSESSION_TIME
	highlight_timer = CATCH_COMPLETE_TIME
	_successes += 1
	player.set_pulse(false)
	ui.set_phase_status("CAUGHT")
	# The coach only reports a caught feed when the token took it cleanly (see
	# CoachThrower._clean_catch), so reaching here is the perfect catch that the
	# avatar reacts to.
	ui.avatar_catch_made()
	ui.show_message("Clean catch! Next feed incoming.", true)
	ui.set_instruction(SHOT_HINT)
	queue_redraw()


## The feed landed away from the token, so the ball sits where it landed and the
## player has one chase to reach it. The clock only runs while the player is free
## to move, so a committed route always plays out.
func _begin_loose_ball() -> void:
	_throw_pending = false
	_ball_out = false
	_ball_loose = true
	# The ball is wherever it came to rest, which is no longer the cell the feed
	# was aimed at once it has bounced on.
	_loose_cell = coach.ball_cell() if coach != null else target_cell
	_loose_timer = LOOSE_BALL_TIME
	player.set_pulse(true)
	ui.set_phase_status("LOOSE BALL")
	# The feed came down without being taken, so this is a missed catch: one in a
	# row reads sad, two in a row tips the avatar over into angry.
	ui.avatar_catch_missed()
	ui.show_message("Feed not caught - chase the ball!", false)
	ui.set_instruction("Drag onto the ball at (%d,%d) before it is lost." % [_loose_cell.x, _loose_cell.y])
	queue_redraw()


func _lose_loose_ball() -> void:
	_ball_loose = false
	state = State.MISS
	_miss_timer = 1.2
	player.set_pulse(false)
	ui.set_phase_status("MISS")
	ui.show_message("Ball lost - next feed loading.", false)
	ui.set_instruction("")
	queue_redraw()


## The feed touched down outside the court: a miss. The next coach move is set up
## once the miss beat has passed, exactly like a lost loose ball.
func _feed_out_of_bounds() -> void:
	_throw_pending = false
	_ball_out = false
	_ball_loose = false
	state = State.MISS
	_miss_timer = 1.4
	player.set_pulse(false)
	ui.set_phase_status("OUT OF BOUNDS")
	# A feed that lands out of court was never taken, so it counts as a missed
	# catch for the avatar.
	ui.avatar_catch_missed()
	ui.show_message("Feed out of bounds - miss.", false)
	ui.set_instruction("")
	queue_redraw()


## The shot window ran out with no shot taken, so this possession is classed as a
## missed shot and the coach feeds the next ball. It settles through the same
## miss beat as a lost loose ball, and reports the miss through
## report_shot_result() so the avatar reacts now exactly as it will to a real
## missed shot: adding shooting later only means calling this from the shot
## instead of from the clock.
func _shot_window_expired() -> void:
	_has_ball = false
	report_shot_result(false)
	state = State.MISS
	_miss_timer = 1.2
	player.set_pulse(false)
	ui.set_phase_status("NO SHOT - MISS")
	ui.show_message("No shot taken - missed.", false)
	ui.set_instruction("")
	queue_redraw()


## --- Shot outcome seam -------------------------------------------------------
## The avatar has a rule for shots - a perfect shot reads excited, a missed shot
## reads angry - but this prototype has no shooting yet, so nothing calls this
## today. When a shot exists, call it from wherever the shot is settled:
## report_shot_result(true) for a perfect shot, report_shot_result(false) for a
## miss. It routes through the same UI seam as the catches, so the avatar stays
## the one place that owns the player's face.
func report_shot_result(made: bool) -> void:
	if made:
		ui.avatar_shot_made()
	else:
		ui.avatar_shot_missed()


## --- Shot power meter ---------------------------------------------------------
## The meter is the display half of a shot the prototype does not have yet: it
## comes up while the token holds the ball, and the range it asks for is sized
## from how far the token stands from the post at POST_CELL - stood under the
## post wants little power, a shot from the far end wants nearly all of it.
## Nothing consumes the power value: no input is read and no shot is fired, so
## the gauge sweeps its own needle and this only keeps it in step with
## possession and distance. A future shooting move should drive the needle with
## set_shot_power(), judge the result with shot_power_required_range() and
## report it through report_shot_result(made) above.


## Keeps the meter in step with the round. Pushed every frame because the token
## can still be walking its route while it holds the ball; the gauge itself skips
## the work when the distance has not changed.
func _sync_power_gauge() -> void:
	if _has_ball != _gauge_shown:
		_gauge_shown = _has_ball
		ui.set_power_gauge_visible(_has_ball)
	if _has_ball:
		ui.set_power_gauge_distance(_distance_to_post_cells())
	# The direction meter appears only once a power value has been selected, and
	# it tracks the token while it still holds the ball: the optimal direction is
	# measured from wherever the token is standing, and it can still be walking.
	var direction_shown := _has_ball and _selected_power >= 0.0
	if direction_shown != _direction_shown:
		_direction_shown = direction_shown
		ui.set_direction_gauge_visible(direction_shown)
	if direction_shown:
		ui.set_direction_gauge_optimal(_optimal_direction_t())


## The player pressed down while holding the ball, so the meter starts charging
## the needle from zero. Pressing again during the same possession restarts it.
func _begin_power_charge() -> void:
	if not _has_ball:
		return
	ui.begin_power_charge()
	ui.set_instruction(SHOT_HINT)


## The player let go, so the value the needle reached is the power they selected
## and the shot direction meter comes up against it: a direction is chosen
## against a power that is already locked. Nothing fires yet - the shot itself is
## still not built - so the possession window goes on running down and still ends
## as a missed shot.
func _release_power_charge() -> void:
	if not _has_ball:
		return
	ui.release_power_charge()
	_selected_power = ui.power_gauge_power()
	ui.set_direction_gauge_optimal(_optimal_direction_t())
	ui.set_instruction("Shot power set at %d%% - choose a direction." % roundi(_selected_power * 100.0))


## Straight-line distance from the token to the post, in court cells. Corner to
## corner is about 14.1 cells, which is what the meter's range is scaled from.
func _distance_to_post_cells() -> float:
	return (Vector2(player_cell) - Vector2(POST_CELL)).length()


## Where the best shot direction sits on the direction dial, 0 = dial left end and
## 1 = dial right end. It is the direction from the token to the post, read in
## screen space: the court is drawn in the 3/4 projection, so the dial has to
## read the projected direction the player can actually see, not the logical grid
## one. The dial sweeps the upper half of the screen's directions, so a post
## straight out to the right of the token lands at the dial's right end, one
## straight up the screen lands mid-dial, and one to the left lands at the left
## end. A post below the token has no place on the upper half of the dial, so it
## clamps to the nearest end.
func _optimal_direction_t() -> float:
	var v: Vector2 = grid_to_screen(POST_CELL) - player.position
	if v.length() < 0.001:
		return 0.5
	# Screen angle: 0 deg points right, -90 deg points up the screen. The dial
	# runs from pointing left (-180 deg) through pointing up to pointing right, so
	# that half turn maps straight onto 0..1 across the dial.
	var deg := rad_to_deg(atan2(v.y, v.x))
	return clampf((deg + 180.0) / 180.0, 0.0, 1.0)


## One line of shot state for the developer debug panel.
func _power_debug_text() -> String:
	if not _has_ball:
		return "no ball"
	var band: Vector2 = ui.power_gauge_required_range()
	# The selected value only exists after a hold-and-release, so it reads "-"
	# until the player has chosen one.
	var shot_txt := ", shot -"
	if _selected_power >= 0.0:
		var valid: Vector2 = ui.direction_gauge_valid_range()
		shot_txt = ", shot %d%%, dir %d-%d%%" % [
			roundi(_selected_power * 100.0),
			roundi(valid.x * 100.0), roundi(valid.y * 100.0)]
	return "holding %.1f cells, need %d-%d%%, %.1fs left%s" % [
		_distance_to_post_cells(), roundi(band.x * 100.0), roundi(band.y * 100.0),
		maxf(_complete_timer, 0.0), shot_txt]


## True while the token is holding the ball.
func has_ball() -> bool:
	return _has_ball


## The power range an accurate shot needs from the token's current cell, as a
## (low, high) pair in 0..1.
func shot_power_required_range() -> Vector2:
	return ui.power_gauge_required_range()


## Drives the needle from outside, for a shooting move that charges its own
## power instead of the meter's preview sweep.
func set_shot_power(value: float) -> void:
	ui.set_power_gauge_power(value)


## Marks where the feed will land. It reads the coach's deterministic destination
## and closes onto it before the ball arrives, so the incoming feed can be read
## and run onto.
func _draw_destination_indicator() -> void:
	if coach == null or not coach.indicator_visible():
		return
	var cell := coach.destination()
	var t := coach.indicator_progress()
	var logical := court_rect.position + Vector2(cell.x * cell_w, cell.y * cell_h)
	var ball_r: float = player.radius * 1.18
	var ring := lerpf(ball_r * 3.2, ball_r * 1.25, t)
	var pulse := 0.5 + 0.5 * sin(_phase * 7.0)
	var col := Color(1.0, 0.86, 0.28, lerpf(0.95, 0.55, t))
	draw_polyline(_floor_ellipse(logical, ring), col, 4.0, true)
	draw_polyline(_floor_ellipse(logical, ring * 0.62),
			Color(col.r, col.g, col.b, col.a * (0.35 + 0.4 * pulse)), 2.0, true)
	if t < 0.35:
		var flash := 1.0 - t / 0.35
		draw_colored_polygon(_floor_ellipse(logical, lerpf(ball_r * 1.5, ball_r * 1.1, t)),
				Color(1, 1, 1, 0.28 * flash))


func _coach_debug_text() -> String:
	if coach == null:
		return "-"
	# The debug line follows the ball, not the intended landing spot: once the feed
	# starts bouncing, where the ball actually is is what matters.
	var ball := _collect_cell()
	var txt := "%s -> ball (%d,%d)" % [coach.phase_name(), ball.x, ball.y]
	if _ball_loose:
		txt += " [loose %.1fs]" % maxf(_loose_timer, 0.0)
	return txt
