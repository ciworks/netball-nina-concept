class_name CoachThrower
extends Node2D
## Sideline coach that feeds the ball into the court.
##
## One feed runs as a fixed sequence of phases:
##   pick spot (pop in with ball) -> hold -> windup -> release -> flight -> catch -> rest
##
## The hold is a variable delay, never shorter than HOLD_MIN: it is sized from how
## far the token has to run to the landing spot and how long the feed is, with the
## destination ring already up, so the player can read the feed and get there.
##
## The ball is thrown as a real projectile. Gravity and the vertical launch
## speed come from the arc the feed should trace, and the horizontal speed is set
## so the FIRST bounce lands exactly on the destination - which is what keeps the
## feed's targeting meaningful. After that bounce nothing is aimed: the ball
## carries on the way it was thrown, losing height on each bounce and speed to the
## floor, until the token takes it, it runs out of momentum, or it touches down
## outside the court.
##
## The catch is judged on contact: the ball's landing point is compared with the
## cell Main reports through player_cell_provider, so the token has to be on the
## ball when it arrives. Reaching it mid-flight is fine, because the ball is judged
## where it actually comes down; arriving after it has touched down is too late.
##
## The throw always starts on the top line, which in this court view is the
## court's upper horizontal edge, i.e. logical y == 0. Cells run 0..GRID_MAX
## along that line; the two corner cells are skipped as throwing spots so a feed
## is never a pure diagonal.
##
## Placeholder art: the coach is a flat block figure drawn in _draw() from
## primitives, so it needs no texture and no scene node. Replace _draw() with an
## AnimatedSprite2D when real art arrives.
##
## Main owns the round: it calls start_round() with the cell the ball must land
## on, then listens for throw_resolved(caught, destination).

## Emitted once, the instant the ball comes to rest. `caught` is the verdict;
## `destination` is the cell the ball last touched down on.
signal throw_resolved(caught: bool, destination: Vector2i)

## Emitted when the ball touches down outside the court: past the bottom
## transverse line (logical y > GRID_MAX) or beyond the right goal line
## (x > GRID_MAX). The feed is dead and Main resets to the next coach move.
signal ball_out_of_bounds(cell: Vector2i)

enum Phase { IDLE, HOLD, WINDUP, RELEASE, FLIGHT, REST }

const GRID_MAX := 10
## The coach feeds from the top line of the court (logical y == 0), which the
## court view draws as the upper horizontal line. Spots along it are x values.
const TOPLINE_Y := 0
const SPOT_MIN := 1
const SPOT_MAX := 9

## How long the coach stands holding the ball before throwing, in seconds. The
## delay grows with how far the token has to run to the landing spot - the ring is
## already up, so that is the player's window to read the feed and get there -
## and, more weakly, with the length of the feed itself. HOLD_MIN is the floor:
## the coach never throws sooner than this. See _hold_delay().
const HOLD_MIN := 1.0
const HOLD_MAX := 7.0
const HOLD_PER_PLAYER_CELL := 0.30
const HOLD_PER_THROW_CELL := 0.10

## Throw timing, in seconds.
const WINDUP_TIME := 0.5
const RELEASE_TIME := 0.14
const REST_TIME := 0.7

## Flight timing and arc height, both scaled by the throw distance so a short
## feed is quick and flat and a long one hangs. Peak height is in cell-heights.
const FLIGHT_BASE := 0.42
const FLIGHT_PER_CELL := 0.075
const FLIGHT_MIN := 0.5
const FLIGHT_MAX := 1.5
const ARC_BASE := 1.3
const ARC_PER_CELL := 0.18
const ARC_MAX := 2.5

## Real ball physics, in court-cell units. The first bounce is aimed at the
## destination; after that the ball keeps travelling the way it was thrown,
## losing height to BALL_RESTITUTION and forward speed to BALL_FRICTION on each
## bounce, until it is taken, runs out of steam, or leaves the court.
const BALL_RESTITUTION := 0.52
const BALL_FRICTION := 0.82
## A bounce lower than BALL_MIN_BOUNCE, or a roll slower than BALL_ROLL_MIN,
## ends the feed: the ball has settled where it stopped.
const BALL_MIN_BOUNCE := 0.7
const BALL_ROLL_MIN := 0.9
## How close, in court cells, the token has to be to a bouncing ball to take it.
const CATCH_RADIUS := 0.75

## Player collision. A token that has been standing on its cell for at least
## SETTLED_TIME takes the ball cleanly every time. A token that has only just
## arrived - or is still on its way - is not set for the ball: it then takes it
## only on a roll of CATCH_CHANCE, and the rest of the time the ball REBOUNDS off
## the player and stays live.
const SETTLED_TIME := 0.5
const CATCH_CHANCE := 0.5
## How much pace the ball keeps when it comes off the player, and how long it
## stays untouchable afterwards so it can clear the player's reach before it can
## be contested again.
const PLAYER_BOUNCE := 0.7
const REBOUND_LOCK := 0.35

## How long the destination ring takes to close onto the landing spot.
const INDICATOR_LOCK := 0.7

## Placeholder figure proportions, measured in court cells. FIGURE_SCALE shrinks
## the drawn figure only - the ball below keeps the court's true scale - so the
## coach stays clear of the UI strip along the top of the screen.
const FIGURE_SCALE := 0.75
const BODY_W := 0.46
const BODY_H := 1.35
## The carry point sits forward of the coach along logical +y, i.e. out into the
## court away from the top line it stands on, so the ball reads as held out in
## front of the body rather than tucked behind it.
const CARRY_FWD := 0.17
const CARRY_HEIGHT := 0.55

## Arm angles in screen space: 0 points straight down, PI/2 points along the
## throw direction (screen +x), PI points straight up. The arm swings up and
## back behind the head, then snaps down and forward through the release.
const ARM_REST := 1.25
const ARM_WINDUP := 3.7
const ARM_RELEASE := 1.0

const BODY_COLOR := Color(0.20, 0.26, 0.40, 1.0)
const BODY_DARK := Color(0.14, 0.18, 0.30, 1.0)
const BODY_ACCENT := Color(0.92, 0.34, 0.24, 1.0)
const SKIN_COLOR := Color(0.93, 0.76, 0.60, 1.0)
const BALL_COLOR := Color(0.90, 0.36, 0.16, 1.0)

## Injected by Main: asks what the token's cell is at the moment the ball lands.
var player_cell_provider := Callable()
## Injected by Main: how many seconds the token has been standing on that cell.
## Drives the clean-catch check in _clean_catch().
var player_dwell_provider := Callable()

var _origin := Vector2.ZERO
var _cell_px := Vector2(64.0, 64.0)
var _project := Callable()

var _logical := Vector2(5.0, float(TOPLINE_Y))
var _phase: int = Phase.IDLE
var _timer := 0.0
var _started := false

# Throw.
var _destination := Vector2i(6, 5)
var _flight_from := Vector2.ZERO
var _flight_to := Vector2.ZERO
var _flight_time := 0.6
var _arc_peak := 1.4
var _reveal_t := 0.0
## Seconds left before the ball can be contested again after it has come off the
## player, so a rebound gets clear of the token's reach first.
var _rebound_lock := 0.0

# Ball and pose. _ball_ground is the ball's floor position and _ball_height its
# height above the floor, both in court cells; _ball_vel and _ball_vh are its
# horizontal and vertical velocities and _ball_g this throw's gravity.
var _ball_ground := Vector2.ZERO
var _ball_height := 0.0
var _air_ratio := 0.0
var _ball_vel := Vector2.ZERO
var _ball_vh := 0.0
var _ball_g := 30.0
var _arm := ARM_REST
var _lean := Vector2.ZERO
var _indicator := false
var _pose_phase := 0.0


func _ready() -> void:
	# Above the court layers (z -1) and below the player token (z 10).
	z_index = 5
	_carry_ball()
	_place()


## Main calls this on every court layout so the coach keeps its size and its
## position relative to the court when the viewport resizes. `project` is Main's
## logical-to-screen court projection, so the coach rides the same geometry
## as the floor and the token.
func layout(court_origin: Vector2, cell_px: Vector2, project: Callable) -> void:
	_origin = court_origin
	_cell_px = cell_px
	_project = project
	_place()


## Starts one feed to `destination`. The coach does not walk between feeds: it
## simply appears at a fresh spot on the top line, ball already in hand, and
## throws from there after a variable hold. The spot is picked before the move so
## the coach is never placed back on the spot it was already standing on.
func start_round(destination: Vector2i) -> void:
	_started = true
	_destination = Vector2i(
		clampi(destination.x, 0, GRID_MAX),
		clampi(destination.y, 0, GRID_MAX))
	var spot := _pick_spot()
	_logical = Vector2(spot, float(TOPLINE_Y))
	_arm = ARM_REST
	_lean = Vector2.ZERO
	_air_ratio = 0.0
	_carry_ball()
	_place()
	# The hold: the coach stands with the ball in hand, destination ring up, for
	# a delay sized from this spot and where the token currently is.
	_timer = _hold_delay()
	_reveal_t = 0.0
	_indicator = true
	_phase = Phase.HOLD
	_rebound_lock = 0.0


func _process(delta: float) -> void:
	_pose_phase += delta
	if _indicator:
		_reveal_t += delta
	if _rebound_lock > 0.0:
		_rebound_lock -= delta
	match _phase:
		Phase.HOLD:
			_process_hold(delta)
		Phase.WINDUP:
			_process_windup(delta)
		Phase.RELEASE:
			_process_release(delta)
		Phase.FLIGHT:
			_process_flight(delta)
		Phase.REST:
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.IDLE
		_:
			# At rest the stance settles and the arm keeps a little idle life.
			_lean = _lean.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
			_arm = lerpf(_arm, ARM_REST + sin(_pose_phase * 1.6) * 0.05,
					clampf(delta * 4.0, 0.0, 1.0))
	queue_redraw()


# --- feed sequence -----------------------------------------------------------

## How long the coach stands holding the ball before the throw. The delay grows
## with how far the token has to run to the landing spot - the ring is already up,
## so that is the player's window to read the feed and get there - and, more
## weakly, with the length of the feed itself. Never below HOLD_MIN.
func _hold_delay() -> float:
	var player_cell: Vector2i = _destination
	if player_cell_provider.is_valid():
		player_cell = player_cell_provider.call()
	# Orthogonal grid steps, because the token only ever moves along rows and
	# columns, so the run the player actually has to make is the city-block one.
	var run_dist := float(absi(player_cell.x - _destination.x) + absi(player_cell.y - _destination.y))
	var throw_dist := _logical.distance_to(Vector2(float(_destination.x), float(_destination.y)))
	var delay := HOLD_MIN + run_dist * HOLD_PER_PLAYER_CELL + throw_dist * HOLD_PER_THROW_CELL
	return clampf(delay, HOLD_MIN, HOLD_MAX)


## The hold itself: the coach stands with the ball while the destination ring
## settles onto the landing spot, then winds up. A little sway in the arm keeps
## the stance alive while it waits.
func _process_hold(delta: float) -> void:
	_timer -= delta
	_arm = lerpf(_arm, ARM_REST + sin(_pose_phase * 1.6) * 0.06,
			clampf(delta * 4.0, 0.0, 1.0))
	if _timer <= 0.0:
		_begin_windup()


## The hold is over, so the arm goes back. The ring is not reset here: it went up
## when the hold started and stays locked on the landing spot until the catch is
## resolved.
func _begin_windup() -> void:
	_phase = Phase.WINDUP
	_timer = WINDUP_TIME
	_arm = ARM_WINDUP
	_indicator = true
	_carry_ball()


func _process_windup(delta: float) -> void:
	_timer -= delta
	# A small extra reach at the top of the backswing.
	_arm = _arm * (1.0 - clampf(delta * 3.0, 0.0, 1.0)) \
		+ (ARM_WINDUP + 0.22) * clampf(delta * 3.0, 0.0, 1.0)
	if _timer <= 0.0:
		_phase = Phase.RELEASE
		_timer = RELEASE_TIME


func _process_release(delta: float) -> void:
	_timer -= delta
	_arm = lerpf(_arm, ARM_RELEASE, clampf(delta * 22.0, 0.0, 1.0))
	if _timer <= 0.0:
		_arm = ARM_RELEASE
		_launch()


func _launch() -> void:
	_phase = Phase.FLIGHT
	_flight_from = _carry_point()
	_flight_to = Vector2(float(_destination.x), float(_destination.y))
	var span := _flight_from.distance_to(_flight_to)
	_flight_time = clampf(FLIGHT_BASE + span * FLIGHT_PER_CELL, FLIGHT_MIN, FLIGHT_MAX)
	_arc_peak = clampf(ARC_BASE + span * ARC_PER_CELL, ARC_BASE, ARC_MAX)
	# The throw is a real projectile. Gravity and the vertical launch speed come
	# from the arc this feed should trace (peak height over the flight time); the
	# horizontal speed is then set so the FIRST bounce lands exactly on the
	# destination, which is what keeps the feed's targeting meaningful. After that
	# bounce nothing is aimed: the ball carries on the way it was thrown.
	_ball_g = 8.0 * _arc_peak / maxf(_flight_time * _flight_time, 0.001)
	_ball_vh = 4.0 * _arc_peak / maxf(_flight_time, 0.001)
	_ball_ground = _flight_from
	_ball_height = CARRY_HEIGHT
	_ball_vel = Vector2.ZERO
	_air_ratio = 0.0
	# Time from release until the ball first reaches the floor, so the horizontal
	# speed covers the throw distance in exactly that time.
	var land_time := (_ball_vh + sqrt(_ball_vh * _ball_vh + 2.0 * _ball_g * CARRY_HEIGHT)) / _ball_g
	if span > 0.001 and land_time > 0.001:
		_ball_vel = (_flight_to - _flight_from) / land_time


func _process_flight(delta: float) -> void:
	# Real motion: the ball keeps the horizontal velocity it was thrown with,
	# while gravity pulls it down. The step is clamped so a frame hitch cannot
	# teleport the ball past a bounce or over a boundary line.
	var step := minf(delta, 0.05)
	_ball_ground += _ball_vel * step
	_ball_vh -= _ball_g * step
	_ball_height += _ball_vh * step
	_air_ratio = clampf(_ball_height / maxf(_arc_peak + CARRY_HEIGHT, 0.001), 0.0, 1.0)
	_arm = lerpf(_arm, ARM_RELEASE + 0.35, clampf(delta * 5.0, 0.0, 1.0))
	if _ball_height <= 0.0 and _ball_vh < 0.0:
		_bounce()


## The ball has touched down. It bounces - losing height to BALL_RESTITUTION and
## forward speed to BALL_FRICTION - unless the token is there to take it, it has
## run out of energy, or it has touched down outside the court.
func _bounce() -> void:
	_ball_height = 0.0
	var cell := _floor_cell(_ball_ground)
	if _is_out_of_bounds(_ball_ground):
		_finish_feed(false, true, cell)
		return
	# Ball against player. The token takes it cleanly if it was set on the spot;
	# a token that has only just arrived gets a roll of the dice, and otherwise
	# the ball comes off it and stays live.
	if _rebound_lock <= 0.0 and _token_is_at(_ball_ground):
		if _clean_catch():
			_finish_feed(true, false, cell)
			return
		_rebound()
		return
	_ball_vh = -_ball_vh * BALL_RESTITUTION
	_ball_vel *= BALL_FRICTION
	# Too little bounce left, or too slow a roll, to keep the ball alive: it
	# settles where it stopped and becomes a loose ball to chase.
	if _ball_vh < BALL_MIN_BOUNCE or _ball_vel.length() < BALL_ROLL_MIN:
		_finish_feed(false, false, cell)


## True when the token takes the ball cleanly. A token that has been standing on
## its cell for at least SETTLED_TIME takes it every time. One that is still
## arriving - or was on the move - has not had time to set itself, so the ball is
## only held on a roll of CATCH_CHANCE; the rest of the time it comes off the
## player as a rebound.
func _clean_catch() -> bool:
	var dwell := 0.0
	if player_dwell_provider.is_valid():
		dwell = player_dwell_provider.call()
	if dwell >= SETTLED_TIME:
		return true
	return randf() < CATCH_CHANCE


## The ball hits the token and comes off it. The throw direction is reflected and
## the ball keeps most of its pace, so it carries on away from the player and
## stays live: it can still be chased, bounce out of the court for a miss, or
## run out of steam and settle. REBOUND_LOCK keeps it uncontested for a moment so
## it can clear the token's reach instead of being grabbed on the same frame.
func _rebound() -> void:
	_ball_vel = -_ball_vel * PLAYER_BOUNCE
	_ball_vh = maxf(absf(_ball_vh) * BALL_RESTITUTION, BALL_MIN_BOUNCE * 1.5)
	_rebound_lock = REBOUND_LOCK
	_air_ratio = 0.0


## Ends the feed. Out of bounds is reported to Main as a miss; otherwise the token
## either took the ball on this bounce or the ball has settled on the floor.
func _finish_feed(caught: bool, out_of_bounds: bool, cell: Vector2i) -> void:
	_phase = Phase.REST
	_timer = REST_TIME
	_indicator = false
	_ball_vh = 0.0
	_ball_vel = Vector2.ZERO
	_ball_ground = Vector2(float(cell.x), float(cell.y))
	_ball_height = 0.0
	_air_ratio = 0.0
	if out_of_bounds:
		ball_out_of_bounds.emit(cell)
		return
	throw_resolved.emit(caught, cell)


## True when the token is standing close enough to `p` to take a bouncing ball.
## Main reports the token's cell, so this compares the token's position with the
## ball's actual landing point rather than cell against cell.
func _token_is_at(p: Vector2) -> bool:
	if not player_cell_provider.is_valid():
		return false
	var pc: Vector2i = player_cell_provider.call()
	return Vector2(float(pc.x), float(pc.y)).distance_to(p) <= CATCH_RADIUS


## The court cell a floor point falls in.
func _floor_cell(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.y))


## True once the ball has touched down outside the court: past the bottom
## transverse line (line y == GRID_MAX) or beyond the right side goal line
## (line x == GRID_MAX). The left end is drawn open and the top line is the
## coach's own, so neither of those counts.
func _is_out_of_bounds(p: Vector2) -> bool:
	return p.x > float(GRID_MAX) or p.y > float(GRID_MAX)


## A fresh throwing spot on the top line: never the spot already occupied, and
## never directly beside the destination when the destination is on the top line
## itself (a feed from the neighbouring cell would be a pure sideways push).
func _pick_spot() -> float:
	var options: Array[float] = []
	for s in range(SPOT_MIN, SPOT_MAX + 1):
		if _destination.y == TOPLINE_Y and s == _destination.x:
			continue
		if absf(float(s) - _logical.x) <= 0.001:
			continue
		options.append(float(s))
	if options.is_empty():
		return _logical.x
	return options[randi() % options.size()]


# --- readouts for Main -------------------------------------------------------

## True once the first feed has been set up, so Main knows to draw the ball from
## this node instead of its own resting position.
func round_active() -> bool:
	return _started


func destination() -> Vector2i:
	return _destination


## True while the destination ring should be on screen.
func indicator_visible() -> bool:
	return _indicator


## 0 when the ring first appears, 1 once it has closed onto the landing spot.
func indicator_progress() -> float:
	return clampf(_reveal_t / INDICATOR_LOCK, 0.0, 1.0)


## True from the moment the coach takes its spot until the ball leaves the hand:
## the coach draws the ball itself during these phases, the whole hold included.
func ball_in_hand() -> bool:
	return _phase == Phase.HOLD or _phase == Phase.WINDUP or _phase == Phase.RELEASE


## True while the ball is travelling, so Main can hold off settling a walk that
## already reached the target cell.
func ball_airborne() -> bool:
	return _phase == Phase.RELEASE or _phase == Phase.FLIGHT


func air_height_ratio() -> float:
	return _air_ratio


## The ball's floor point in logical court space, used for its ground shadow.
func ball_floor_logical() -> Vector2:
	return _ball_ground


## The ball's on-screen position, lifted by the arc height.
func ball_screen() -> Vector2:
	return _to_screen(_ball_ground) - Vector2(0.0, _ball_height * _cell_px.y)


## The court cell the ball's floor point is currently in: the landing cell while
## it is bouncing, or where it settled once the feed has ended.
func ball_cell() -> Vector2i:
	return _floor_cell(_ball_ground)


func phase_name() -> String:
	match _phase:
		Phase.HOLD: return "hold"
		Phase.WINDUP: return "windup"
		Phase.RELEASE: return "release"
		Phase.FLIGHT: return "flight"
		Phase.REST: return "rest"
	return "idle"


# --- geometry and drawing ----------------------------------------------------

func _carry_point() -> Vector2:
	return Vector2(_logical.x, float(TOPLINE_Y) + CARRY_FWD)


func _carry_ball() -> void:
	_ball_ground = _carry_point()
	_ball_height = CARRY_HEIGHT
	_air_ratio = 0.0


## The ball in this node's local space, so _draw() can place it directly.
func _ball_local() -> Vector2:
	return _to_screen(_ball_ground) - position - Vector2(0.0, _ball_height * _cell_px.y)


func _place() -> void:
	position = _to_screen(_logical)


func _to_screen(p: Vector2) -> Vector2:
	if not _project.is_valid():
		return position
	var sp: Vector2 = _project.call(
		_origin + Vector2(p.x * _cell_px.x, p.y * _cell_px.y))
	return sp


func _draw() -> void:
	var cw := _cell_px.x
	var ch := _cell_px.y
	# The figure's own metrics carry FIGURE_SCALE; cw/ch stay at their true cell
	# size for anything that has to match the court, such as the ball radius.
	var fig := FIGURE_SCALE
	var body_w := cw * BODY_W * fig
	var body_h := maxf(ch * BODY_H * fig, 18.0)
	var head := maxf(cw * 0.28 * fig, 6.0)
	var top := -body_h
	var bc := _lean

	# Contact shadow on the floor, flattened by the court view.
	draw_set_transform(Vector2(0.0, 2.0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, body_w * 0.7, Color(0, 0, 0, 0.20))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# The ball is drawn last (see below), so it reads as being in front of the
	# figure both while carried and all the way through the arc.

	# Legs.
	var leg_w := body_w * 0.18
	var leg_h := body_h * 0.26
	draw_rect(Rect2(Vector2(-body_w * 0.30 + bc.x, -leg_h), Vector2(leg_w, leg_h)), BODY_DARK, true)
	draw_rect(Rect2(Vector2(body_w * 0.12 + bc.x, -leg_h), Vector2(leg_w, leg_h)), BODY_DARK, true)

	# Throwing arm, drawn before the torso so the shoulder reads as attached to
	# the body rather than pasted on top of it.
	var shoulder := Vector2(-cw * 0.05 * fig + bc.x, top + body_h * 0.16 + bc.y)
	var arm_len := body_h * 0.62
	var hand := shoulder + Vector2(sin(_arm), cos(_arm)) * arm_len
	draw_line(shoulder, hand, BODY_ACCENT, maxf(body_w * 0.18, 3.0), true)

	# Torso, with a shirt band across the shoulders.
	var torso := Rect2(Vector2(-body_w * 0.5 + bc.x, top + bc.y), Vector2(body_w, body_h * 0.82))
	draw_rect(torso, BODY_COLOR, true)
	draw_rect(Rect2(torso.position, Vector2(body_w, maxf(ch * 0.10 * fig, 3.0))), BODY_ACCENT, true)
	draw_rect(torso, Color(0, 0, 0, 0.35), false, 1.5)

	# Head.
	var head_c := Vector2(bc.x, top - head * 0.75 + bc.y)
	draw_circle(head_c, head, SKIN_COLOR)
	draw_arc(head_c, head, 0.0, TAU, 24, Color(0, 0, 0, 0.35), 1.5, true)

	# Hand at the end of the arm.
	draw_circle(hand, maxf(body_w * 0.16, 3.0), SKIN_COLOR)

	# The coach owns the ball visual from the carry through the entire arc, so it
	# never flickers out mid-flight. The ball rides its lifted position while a
	# shadow stays on the floor beneath it, which is what sells the arc.
	if ball_in_hand() or ball_airborne():
		var br := maxf(cw * 0.283, 5.0)
		var bp := _ball_local()
		var floor_local := _to_screen(_ball_ground) - position
		var lift := clampf(_ball_height / maxf(_arc_peak + CARRY_HEIGHT, 0.001), 0.0, 1.0)
		draw_set_transform(floor_local, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, br * lerpf(0.95, 0.6, lift),
				Color(0, 0, 0, lerpf(0.22, 0.08, lift)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(bp, br, BALL_COLOR)
		draw_arc(bp, br * 0.8, -1.2, 3.3, 16, Color(1, 1, 1, 0.5), 1.5, true)
		draw_circle(bp + Vector2(-br * 0.32, -br * 0.38), br * 0.2, Color(1, 1, 1, 0.55))

	var font := ThemeDB.fallback_font
	var label_pos := Vector2(-70.0, ch * 0.5)
	draw_string(font, label_pos + Vector2(0, 1), "Coach", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(0, 0, 0, 0.35))
	draw_string(font, label_pos, "Coach", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1, 1, 1, 0.95))
