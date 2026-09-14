class_name DirectionGauge
extends Control
## Shot direction meter: a semicircular dial showing which way a shot has to be
## aimed to be on target, and how much room for error there is.
##
## The needle position is a direction across the dial's sweep. The left end is
## aimed left across the screen, the middle is aimed straight up the screen, and
## the right end is aimed right - so the dial reads the way the court is drawn.
## The optimal direction is the direction from the token to the goal post, which
## Main computes and pushes in with set_optimal(). The green arc is the range
## around that optimal direction which still counts as an accurate shot, sized
## by DIRECTION_TOLERANCE either side. Everything outside the green arc is red,
## i.e. an out of bounds shot.
##
## Like the power meter, this is the display half of the mechanic only. Nothing
## selects a direction yet - the shot is not built - so the needle sweeps the
## dial by itself to show where the green range sits from where the token is
## standing. When a direction is chosen, drive the needle with set_direction()
## and judge the choice with in_valid_range().
##
## The dial never takes input. It hangs over the court, and a Control that
## stopped touches there would swallow drag strokes drawn across the screen
## (see the UI mouse filter rule in AGENTS.md).

## The whole dial, in pixels, including the space for its label row.
const DIAL_SIZE := Vector2(300.0, 200.0)

## The needle pivots here, in this control's local space. It sits low so the
## semicircle and its hub fill the control from the top down.
const PIVOT := Vector2(150.0, 172.0)

## The flat grey track the arcs sit inside.
const R_TRACK_OUTER := 138.0
const R_TRACK_INNER := 128.0

## The coloured band: red outside the tolerance, green inside it.
const R_ZONE_INNER := 86.0

## Hub at the pivot, and the needle that swings from it.
const HUB_RADIUS := 17.0
const HUB_CORE_RADIUS := 7.0
const NEEDLE_LENGTH := 120.0
const NEEDLE_WIDTH := 7.0

## How far either side of the optimal direction still counts as on target, as a
## fraction of the dial's sweep. The dial sweeps 180 degrees, so 0.05 either way
## is 9 degrees either way - the tolerance Main reports.
const DIRECTION_TOLERANCE := 0.05

## How fast the preview needle sweeps the dial, in dial units per second.
const SWEEP_SPEED := 0.55

const TRACK_COLOR := Color(0.86, 0.88, 0.90, 0.96)
const VALID_COLOR := Color(0.35, 0.72, 0.30, 1.0)
const INVALID_COLOR := Color(0.85, 0.24, 0.22, 1.0)
const NEEDLE_COLOR := Color(0.16, 0.17, 0.19, 1.0)
const HUB_COLOR := Color(0.16, 0.17, 0.19, 1.0)
const HUB_CORE_COLOR := Color(0.97, 0.97, 0.97, 1.0)
const TEXT_COLOR := Color(0.92, 1.0, 1.0, 0.96)
const TEXT_DIM := Color(0.80, 0.90, 0.94, 0.72)

## Where the optimal direction sits on the dial, 0 (left end) to 1 (right end).
var _optimal := 0.5
## Where the needle is currently pointing, same 0..1 scale.
var _direction := 0.5
var _sweep_dir := 1.0
var _phase := 0.0


func _ready() -> void:
	custom_minimum_size = DIAL_SIZE
	# The dial floats over the court, so it must never consume a touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not visible:
		return
	_phase += delta
	# Preview sweep. Nothing reads a direction yet - the shot that will is not
	# built - so the needle rides the whole dial on its own, which is what shows
	# the player where the green range sits from where they are standing.
	_direction += _sweep_dir * SWEEP_SPEED * delta
	if _direction >= 1.0:
		_direction = 1.0
		_sweep_dir = -1.0
	elif _direction <= 0.0:
		_direction = 0.0
		_sweep_dir = 1.0
	queue_redraw()


## Shows or hides the dial. Every appearance starts the sweep from the left so
## the range always reads the same way.
func set_active(on: bool) -> void:
	visible = on
	if on:
		_direction = 0.0
		_sweep_dir = 1.0
		_phase = 0.0
	queue_redraw()


## The direction that would be on target, 0 (dial left) to 1 (dial right). Main
## sizes this from the token's position against the goal post.
func set_optimal(t: float) -> void:
	_optimal = clampf(t, 0.0, 1.0)
	queue_redraw()


## The optimal direction, as a 0..1 dial position.
func optimal() -> float:
	return _optimal


## The green range: the directions that would still be an accurate shot at the
## current optimal direction, as a (low, high) pair in 0..1.
func valid_range() -> Vector2:
	var lo := clampf(_optimal - DIRECTION_TOLERANCE, 0.0, 1.0)
	var hi := clampf(_optimal + DIRECTION_TOLERANCE, 0.0, 1.0)
	return Vector2(lo, hi)


## True while the needle sits inside the green range: the good shot the dial is
## asking for. Nothing acts on this yet - it tints the needle so the requirement
## can be read.
func in_valid_range() -> bool:
	var r := valid_range()
	return _direction >= r.x and _direction <= r.y


## Drives the needle from outside, for a direction move that replaces the
## preview sweep.
func set_direction(value: float) -> void:
	_direction = clampf(value, 0.0, 1.0)
	queue_redraw()


## The needle's current dial position, 0..1. A future shot reads this as the
## direction it was aimed in.
func direction() -> float:
	return _direction


## Dial position to screen angle. The sweep runs from PI (pointing left) through
## 1.5 PI (pointing up) to TAU (pointing right).
func _angle_for(t: float) -> float:
	return lerpf(PI, TAU, clampf(t, 0.0, 1.0))


## One filled band between two radii across a span of the sweep.
func _wedge(inner_r: float, outer_r: float, t0: float, t1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(4, int(absf(t1 - t0) * 48.0) + 2)
	for i in range(steps + 1):
		var t := lerpf(t0, t1, float(i) / float(steps))
		pts.append(PIVOT + Vector2(cos(_angle_for(t)), sin(_angle_for(t))) * outer_r)
	for i in range(steps, -1, -1):
		var t := lerpf(t0, t1, float(i) / float(steps))
		pts.append(PIVOT + Vector2(cos(_angle_for(t)), sin(_angle_for(t))) * inner_r)
	return pts


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var rng := valid_range()
	var in_range := in_valid_range()

	# Flat grey track behind everything, drawn as one thick arc.
	var r_mid := (R_TRACK_OUTER + R_TRACK_INNER) * 0.5
	var r_width := R_TRACK_OUTER - R_TRACK_INNER
	draw_arc(PIVOT, r_mid, PI, TAU, 96, TRACK_COLOR, r_width, true)

	# The colored band: red everywhere, green over the tolerance around the
	# optimal direction. Red is drawn as the two spans either side of the green
	# so the green always sits on top and stays exactly the tolerance wide.
	if rng.x > 0.001:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, 0.0, rng.x), INVALID_COLOR)
	if rng.y < 0.999:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, rng.y, 1.0), INVALID_COLOR)
	if rng.y - rng.x > 0.001:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, rng.x, rng.y), VALID_COLOR)

	# Needle: a tapered blade from the hub, brightened while it is on target.
	var ang := _angle_for(_direction)
	var tip := PIVOT + Vector2(cos(ang), sin(ang)) * NEEDLE_LENGTH
	var side := Vector2(-sin(ang), cos(ang)) * (NEEDLE_WIDTH * 0.5)
	var blade := PackedVector2Array([
		PIVOT + side,
		PIVOT - side,
		tip,
	])
	draw_colored_polygon(blade, NEEDLE_COLOR)
	if in_range:
		var glow := 0.5 + 0.5 * sin(_phase * 8.0)
		draw_circle(tip, 7.0 + glow * 3.0,
				Color(VALID_COLOR.r, VALID_COLOR.g, VALID_COLOR.b, 0.18 + 0.14 * glow))

	# Hub: the dark cap the needle turns on, with its light centre.
	draw_circle(PIVOT, HUB_RADIUS, HUB_COLOR)
	draw_circle(PIVOT, HUB_CORE_RADIUS, HUB_CORE_COLOR)

	# Label row above the arc.
	draw_string(font, Vector2(12.0, 18.0), "SHOT DIRECTION",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	var tol_pct := roundi(DIRECTION_TOLERANCE * 100.0)
	var readout := "ON TARGET" if in_range else "OPTIMAL +-%d%%" % tol_pct
	var readout_col := VALID_COLOR if in_range else TEXT_DIM
	var text_w := font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(DIAL_SIZE.x - 12.0 - text_w, 18.0), readout,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, readout_col)
