class_name ShotMeter
extends Control
## The combined shot meter: the power bar and the direction dial in one control.
##
## The meter is shown while the token holds the ball. It has two halves, and they
## are selected in order because the second is only meaningful once the first is
## settled:
##
## 1. Power (left). Hold anywhere to charge the needle from zero, let go to lock
##    the value in. The band over the bar is the range that would send an
##    accurate shot at the post from where the token is standing: it follows the
##    distance to the post and narrows as that distance grows, and it turns green
##    while the needle sits inside it.
## 2. Direction (right). It is grey and inert until a power value has been
##    locked, then it lights up in its own colours and a hold starts the aim
##    needle sweeping across the dial. The green arc is the range of directions
##    around the optimal one that still counts as on target; the red either side
##    of it is out of bounds. The needle bounces between the two extreme values
##    of the dial while it is held, so the green has to be caught as it goes
##    past, and letting go locks the value it was on - the same hold and release
##    the power bar uses.
##
## Neither half takes input itself. The meter floats over the middle of the court,
## and a Control that stopped touches there would swallow the drag strokes drawn
## across the screen (see the UI mouse filter rule in AGENTS.md). Main reads the
## press and release and drives both halves through this API: begin_aim() does the
## dial's hit test, so a press only starts the sweep when it is meant for the dial.
##
## Main._fire_shot() is what consumes the two selections: it reads power() and
## direction() at the moment the dial is released and judges them against
## required_range() and valid_range() - the same ranges this control is drawing -
## so the picture on the meter and the verdict can never disagree.

## The whole floating panel, in pixels. Wide enough to read as a meter on a phone
## stretched to the 1280x720 base.
const METER_SIZE := Vector2(800.0, 230.0)

## --- Power bar, the left half -------------------------------------------------
## The track the power needle runs along, in this control's local space.
const TRACK := Rect2(28.0, 86.0, 420.0, 50.0)
const TRACK_INSET := 9.0
const BAR_RADIUS := 11
const BAND_RADIUS := 7
const TICK_COUNT := 10

## Distance from the token to the post, in court cells, that the bar maps across
## its full range: MIN is a token stood right under the post, MAX is the longest
## shot this court allows (corner to corner is about 14.1 cells).
const MIN_DISTANCE_CELLS := 1.0
const MAX_DISTANCE_CELLS := 14.0

## Where the required range sits on the bar, as a fraction of full power. A close
## shot wants little power and a long one wants nearly all of it.
const BAND_CENTER_NEAR := 0.18
const BAND_CENTER_FAR := 0.86

## Half-width of the required range: the tolerance the player has to stay inside.
## It tightens with distance, so a shot from the far end is a finer ask.
const BAND_HALF_NEAR := 0.10
const BAND_HALF_FAR := 0.04

## How fast the needle climbs while the player holds it down, in power units per
## second: a full-power hold takes just under a second.
const CHARGE_SPEED := 1.15

## --- Direction dial, the right half -------------------------------------------
## The needle pivots here, low in the panel so the semicircle fills it.
const PIVOT := Vector2(660.0, 166.0)

## The orange trim outside the dial's grey track, so it carries the same edge as
## the power bar.
const R_TRIM := 108.0
const TRIM_WIDTH := 4.0

## The flat grey track the arcs sit inside, and the coloured band inside that.
const R_TRACK_OUTER := 104.0
const R_TRACK_INNER := 95.0
const R_ZONE_INNER := 64.0

## Hub at the pivot, and the needle that swings from it.
const HUB_RADIUS := 13.5
const HUB_CORE_RADIUS := 6.0
const NEEDLE_LENGTH := 89.0
const NEEDLE_WIDTH := 7.0

## How far either side of the optimal direction still counts as on target, as a
## fraction of the dial's sweep. The dial sweeps 180 degrees, so 0.05 either way
## is 9 degrees either way - the tolerance Main reports.
const DIRECTION_TOLERANCE := 0.05

## Where the optimal direction sits before Main has told the dial otherwise:
## straight up the screen, the middle of the sweep.
const DIRECTION_START := 0.5

## How fast the aim needle sweeps the dial while it is held down, in dial units
## per second. A full traverse takes a bit under two seconds, and the green arc
## is 0.10 of the sweep wide, so the needle is inside it for about 180ms at a
## time - a timing window rather than a free choice.
const SWEEP_SPEED := 0.55

## The power bar's own part of the panel, generously padded for a finger. It is
## the one region that is not the dial: a press here re-picks the power, and a
## press anywhere else starts the aim sweep.
const BAR_HIT := Rect2(18.0, 22.0, 442.0, 150.0)

## Text rows of the panel, and the right edge of the dial's text items.
const LABEL_Y := 36.0
const READOUT_Y := 210.0
const LABEL_SIZE := 14
const READOUT_SIZE := 14
const DIAL_TEXT_RIGHT := 772.0
## Left edge of the dial's label, over the dial rather than the bar.
const DIAL_TEXT_LEFT := 534.0

# --- Colours ------------------------------------------------------------------
const PANEL_COLOR := Color(0.03, 0.10, 0.14, 0.78)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.14)
const TRIM_COLOR := Color(0.99, 0.74, 0.20, 0.95)
const BAR_TRACK_COLOR := Color(0.05, 0.11, 0.16, 0.94)
const BAR_FILL_COLOR := Color(0.18, 0.72, 0.38, 0.95)
const BAND_COLOR := Color(0.86, 0.24, 0.21, 0.95)
const BAND_OK_COLOR := Color(0.42, 0.98, 0.58, 0.98)
const BAND_EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const BAR_NEEDLE_COLOR := Color(1.0, 1.0, 1.0, 0.97)
const TICK_COLOR := Color(1.0, 1.0, 1.0, 0.18)

const DIAL_TRACK_COLOR := Color(0.86, 0.88, 0.90, 0.96)
const DIAL_VALID_COLOR := Color(0.35, 0.72, 0.30, 1.0)
const DIAL_INVALID_COLOR := Color(0.85, 0.24, 0.22, 1.0)
const DIAL_NEEDLE_COLOR := Color(0.16, 0.17, 0.19, 1.0)
const DIAL_HUB_COLOR := Color(0.16, 0.17, 0.19, 1.0)
const DIAL_HUB_CORE_COLOR := Color(0.97, 0.97, 0.97, 1.0)

## The dial before a power value is locked: the same shapes, drained of colour, so
## it reads as present but switched off.
const OFF_TRIM_COLOR := Color(0.62, 0.58, 0.48, 0.70)
const OFF_DIAL_TRACK_COLOR := Color(0.46, 0.49, 0.52, 0.80)
const OFF_DIAL_VALID_COLOR := Color(0.40, 0.43, 0.45, 0.90)
const OFF_DIAL_INVALID_COLOR := Color(0.40, 0.43, 0.45, 0.90)
const OFF_DIAL_NEEDLE_COLOR := Color(0.30, 0.32, 0.34, 1.0)
const OFF_DIAL_HUB_COLOR := Color(0.28, 0.30, 0.32, 1.0)
const OFF_DIAL_CORE_COLOR := Color(0.58, 0.60, 0.62, 1.0)

const TEXT_COLOR := Color(0.92, 1.0, 1.0, 0.96)
const TEXT_DIM := Color(0.80, 0.90, 0.94, 0.72)

## Distance the bar is currently reading, in court cells.
var _distance := MIN_DISTANCE_CELLS
## The band of bar positions that would be an accurate shot at _distance.
var _band_lo := 0.0
var _band_hi := 1.0

## Current power needle position, 0..1 across the track.
var _power := 0.0
## True while the player is holding the bar down: the needle only climbs then.
var _charging := false
## True once the player has released on a power value. This is also what switches
## the direction dial on.
var _locked := false

## Where the optimal direction sits on the dial, 0 (left end) to 1 (right end).
var _optimal := DIRECTION_START
## Where the aim needle is pointing, same 0..1 scale.
var _direction := DIRECTION_START
## Which way the aim needle is travelling: 1 sweeping right, -1 sweeping left.
var _sweep_dir := 1.0
## True while the player has the dial held down.
var _aiming := false
## True once the player has released on a direction.
var _direction_locked := false

var _phase := 0.0

# Cached styleboxes - the panel, the bar track, the power fill and the required
# band - so drawing allocates nothing per frame.
var _panel_sb: StyleBoxFlat
var _bar_track_sb: StyleBoxFlat
var _bar_fill_sb: StyleBoxFlat
var _band_sb: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = METER_SIZE
	# The meter hangs over the court, so it must never consume a touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_sb = _make_box(PANEL_COLOR, 18)
	_panel_sb.border_color = PANEL_EDGE
	_panel_sb.set_border_width_all(1)
	_bar_track_sb = _make_box(BAR_TRACK_COLOR, BAR_RADIUS)
	_bar_track_sb.border_color = TRIM_COLOR
	_bar_track_sb.set_border_width_all(3)
	_bar_fill_sb = _make_box(BAR_FILL_COLOR, BAR_RADIUS - 3)
	_band_sb = _make_box(BAND_COLOR, BAND_RADIUS)
	_band_sb.border_color = BAND_EDGE_COLOR
	_recompute_band()


func _process(delta: float) -> void:
	if not visible:
		return
	_phase += delta
	# Hold to charge. The needle climbs only while the player is holding the bar
	# down, and letting go locks it. That lock is also what switches the
	# direction dial on.
	if _charging and not _locked:
		_power = minf(_power + CHARGE_SPEED * delta, 1.0)
	# Hold to aim. The dial's needle sweeps while the player holds it down and
	# bounces at the two extreme values of the dial, so the green arc has to be
	# caught as it goes past rather than sat on. Letting go locks the value the
	# needle was left on.
	if _aiming and not _direction_locked:
		_direction += _sweep_dir * SWEEP_SPEED * delta
		if _direction >= 1.0:
			_direction = 1.0
			_sweep_dir = -1.0
		elif _direction <= 0.0:
			_direction = 0.0
			_sweep_dir = 1.0
	queue_redraw()


## Shows or hides the whole meter. Every possession starts from a clean slate: no
## power, no aim, and the direction dial switched off.
func set_active(on: bool) -> void:
	visible = on
	_power = 0.0
	_charging = false
	_locked = false
	# The dial starts parked at its low end, which is where its sweep begins.
	_direction = 0.0
	_sweep_dir = 1.0
	_aiming = false
	_direction_locked = false
	_phase = 0.0
	queue_redraw()


## --- Power bar ----------------------------------------------------------------


## The player pressed down on the bar, so the needle starts a fresh climb from
## zero. A new power value also means a new direction: the aim is cleared and the
## dial goes back to its switched-off look until this value is locked.
func begin_charge() -> void:
	_charging = true
	_locked = false
	_power = 0.0
	_direction = 0.0
	_sweep_dir = 1.0
	_aiming = false
	_direction_locked = false
	queue_redraw()


## The player let go, so the value the needle reached is the one they selected.
## It stays put until the next hold, and this is what switches the direction dial
## on.
func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	_locked = true
	# This lock is what brings the dial alive, so it starts from the low end of
	# the dial and sweeps right as soon as the player presses again.
	_direction = 0.0
	_sweep_dir = 1.0
	_direction_locked = false
	queue_redraw()


## True once the player has released on a power value, i.e. the selection is made.
func is_locked() -> bool:
	return _locked


## How far the token is from the post, in court cells. This is what sizes the
## required range, so a shot from further out wants more power and a narrower
## band to land in.
func set_distance_cells(cells: float) -> void:
	var d := maxf(cells, 0.0)
	if is_equal_approx(d, _distance):
		return
	_distance = d
	_recompute_band()
	queue_redraw()


## Current power needle position, 0..1. A future shot reads this as the power it
## was given.
func power() -> float:
	return _power


## The band of positions that would be an accurate shot at the current distance,
## as a (low, high) pair in 0..1.
func required_range() -> Vector2:
	return Vector2(_band_lo, _band_hi)


## True while the needle is inside the required range: the accurate shot the bar
## is asking for.
func in_accuracy_band() -> bool:
	return _power >= _band_lo and _power <= _band_hi


## Drives the needle from outside, for a shooting move that drives the value
## itself instead of the player's hold.
func set_power(value: float) -> void:
	_power = clampf(value, 0.0, 1.0)
	queue_redraw()


## --- Direction dial -----------------------------------------------------------


## True once the dial can be aimed: the power value has been locked, so a
## direction means something. Until then the dial is drawn grey and inert.
func direction_active() -> bool:
	return _locked


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


## True while the aim needle sits inside the green range: the good shot the dial
## is asking for.
func in_valid_range() -> bool:
	var r := valid_range()
	return _direction >= r.x and _direction <= r.y


## Drives the needle from outside, for a direction move that drives the value
## itself instead of the player's aim.
func set_direction(value: float) -> void:
	_direction = clampf(value, 0.0, 1.0)
	queue_redraw()


## The aim needle's current dial position, 0..1. A shot reads this as the
## direction it was taken in.
func direction() -> float:
	return _direction


## True while the player has the dial held down and the needle is sweeping.
func aiming() -> bool:
	return _aiming


## True once the player has released on a direction.
func direction_locked() -> bool:
	return _direction_locked


## A press at screen_pos, in viewport coordinates, once the power value is locked.
## The press takes the aim needle unless it landed on the power bar - which is how
## a mis-charged power gets re-picked - so returning true tells Main that the
## needle is held down until they let go. Every aim starts its sweep from the low
## end of the dial, so the timing reads the same way every time.
func begin_aim(screen_pos: Vector2) -> bool:
	if not direction_active():
		return false
	if BAR_HIT.has_point(screen_pos - global_position):
		return false
	_aiming = true
	_direction_locked = false
	_direction = 0.0
	_sweep_dir = 1.0
	queue_redraw()
	return true


## The player let go, so the direction the needle had swept to is the one they
## selected, and the sweep stops there. It stays put until the next aim.
func lock_direction() -> void:
	if not _aiming:
		return
	_aiming = false
	_direction_locked = true
	queue_redraw()


## Dial position to screen angle.
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


func _recompute_band() -> void:
	var span := maxf(MAX_DISTANCE_CELLS - MIN_DISTANCE_CELLS, 0.001)
	var t := clampf((_distance - MIN_DISTANCE_CELLS) / span, 0.0, 1.0)
	var center := lerpf(BAND_CENTER_NEAR, BAND_CENTER_FAR, t)
	var half := lerpf(BAND_HALF_NEAR, BAND_HALF_FAR, t)
	_band_lo = clampf(center - half, 0.0, 1.0)
	_band_hi = clampf(center + half, 0.0, 1.0)


func _make_box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_style_box(_panel_sb, Rect2(Vector2.ZERO, METER_SIZE))
	_draw_power(font)
	_draw_dial(font)


func _draw_power(font: Font) -> void:
	var span_x := TRACK.position.x + TRACK_INSET
	var span_w := maxf(TRACK.size.x - TRACK_INSET * 2.0, 1.0)
	var needle_x := span_x + span_w * _power
	var in_band := in_accuracy_band()
	var tick_cy := TRACK.position.y + TRACK.size.y * 0.5

	draw_string(font, Vector2(TRACK.position.x, LABEL_Y), "SHOT POWER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, TEXT_COLOR)

	# Track, the power generated so far, then a light scale over both.
	draw_style_box(_bar_track_sb, TRACK)
	var fill_w := clampf(needle_x - TRACK.position.x, 0.0, TRACK.size.x)
	if fill_w > 1.0:
		draw_style_box(_bar_fill_sb, Rect2(TRACK.position, Vector2(fill_w, TRACK.size.y)))
	for i in range(1, TICK_COUNT):
		var tx := span_x + span_w * (float(i) / float(TICK_COUNT))
		draw_line(Vector2(tx, tick_cy - 7.0), Vector2(tx, tick_cy + 7.0), TICK_COLOR, 1.0, true)

	# The required range for this distance, drawn over the fill so it stays
	# readable wherever the needle happens to be. It is red while the needle is
	# outside it and turns green, with a white edge and a glow, once the needle
	# is in.
	var band_x0 := span_x + span_w * _band_lo
	var band_x1 := span_x + span_w * _band_hi
	_band_sb.bg_color = BAND_OK_COLOR if in_band else BAND_COLOR
	_band_sb.set_border_width_all(2 if in_band else 0)
	draw_style_box(_band_sb, Rect2(
			Vector2(band_x0, TRACK.position.y + 3.0),
			Vector2(maxf(band_x1 - band_x0, 5.0), TRACK.size.y - 6.0)))
	if in_band:
		var glow := 0.5 + 0.5 * sin(_phase * 8.0)
		draw_circle(Vector2(needle_x, tick_cy), 11.0 + glow * 3.0,
				Color(BAND_OK_COLOR.r, BAND_OK_COLOR.g, BAND_OK_COLOR.b, 0.16 + 0.12 * glow))

	# The needle, with a soft drop shadow so it reads over the band.
	draw_rect(Rect2(Vector2(needle_x - 2.0, TRACK.position.y - 4.0),
			Vector2(6.0, TRACK.size.y + 12.0)), Color(0, 0, 0, 0.35), true)
	draw_rect(Rect2(Vector2(needle_x - 3.0, TRACK.position.y - 7.0),
			Vector2(6.0, TRACK.size.y + 12.0)), BAR_NEEDLE_COLOR, true)

	# Readout row: what the needle is doing and what the bar is asking for.
	var lo_pct := roundi(_band_lo * 100.0)
	var hi_pct := roundi(_band_hi * 100.0)
	var power_txt := "POWER %d%%" % roundi(_power * 100.0)
	if _locked:
		power_txt = "LOCKED AT %d%%" % roundi(_power * 100.0)
	draw_string(font, Vector2(TRACK.position.x, READOUT_Y), power_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_SIZE, TEXT_COLOR)
	_draw_center(font, TRACK.position.x + TRACK.size.x * 0.5, READOUT_Y,
			"REQUIRED %d-%d%%" % [lo_pct, hi_pct], READOUT_SIZE, TEXT_DIM)
	_draw_right(font, TRACK.position.x + TRACK.size.x, READOUT_Y,
			"IN RANGE" if in_band else "OUT OF RANGE", READOUT_SIZE,
			BAND_OK_COLOR if in_band else TEXT_DIM)


func _draw_dial(font: Font) -> void:
	# The whole dial is drawn from a drained palette until the power value is
	# locked: present, but visibly switched off.
	var active := direction_active()
	var trim_col := TRIM_COLOR if active else OFF_TRIM_COLOR
	var track_col := DIAL_TRACK_COLOR if active else OFF_DIAL_TRACK_COLOR
	var valid_col := DIAL_VALID_COLOR if active else OFF_DIAL_VALID_COLOR
	var invalid_col := DIAL_INVALID_COLOR if active else OFF_DIAL_INVALID_COLOR
	var needle_col := DIAL_NEEDLE_COLOR if active else OFF_DIAL_NEEDLE_COLOR
	var hub_col := DIAL_HUB_COLOR if active else OFF_DIAL_HUB_COLOR
	var core_col := DIAL_HUB_CORE_COLOR if active else OFF_DIAL_CORE_COLOR
	var rng := valid_range()
	var in_range := in_valid_range()

	# Orange trim outside the grey track, then the flat grey track itself.
	draw_arc(PIVOT, R_TRIM, PI, TAU, 96, trim_col, TRIM_WIDTH, true)
	draw_arc(PIVOT, (R_TRACK_OUTER + R_TRACK_INNER) * 0.5, PI, TAU, 96, track_col,
			R_TRACK_OUTER - R_TRACK_INNER, true)

	# The coloured band: red everywhere, green over the tolerance around the
	# optimal direction. Red is drawn as the two spans either side of the green
	# so the green always sits on top and stays exactly the tolerance wide.
	if rng.x > 0.001:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, 0.0, rng.x), invalid_col)
	if rng.y < 0.999:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, rng.y, 1.0), invalid_col)
	if rng.y - rng.x > 0.001:
		draw_colored_polygon(_wedge(R_ZONE_INNER, R_TRACK_INNER, rng.x, rng.y), valid_col)

	# Needle: a tapered blade from the hub, brightened while it is on target.
	var ang := _angle_for(_direction)
	var tip := PIVOT + Vector2(cos(ang), sin(ang)) * NEEDLE_LENGTH
	var side := Vector2(-sin(ang), cos(ang)) * (NEEDLE_WIDTH * 0.5)
	draw_colored_polygon(PackedVector2Array([PIVOT + side, PIVOT - side, tip]), needle_col)
	if active and in_range:
		var glow := 0.5 + 0.5 * sin(_phase * 8.0)
		draw_circle(tip, 7.0 + glow * 3.0,
				Color(valid_col.r, valid_col.g, valid_col.b, 0.18 + 0.14 * glow))

	# Hub: the dark cap the needle turns on, with its light centre.
	draw_circle(PIVOT, HUB_RADIUS, hub_col)
	draw_circle(PIVOT, HUB_CORE_RADIUS, core_col)

	# Label row and the state the dial is in.
	draw_string(font, Vector2(DIAL_TEXT_LEFT, LABEL_Y), "SHOT DIRECTION",
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			TEXT_COLOR if active else TEXT_DIM)
	var status := "SET POWER FIRST"
	var status_col := TEXT_DIM
	if active and _direction_locked:
		status = "ON TARGET" if in_range else "OFF TARGET"
		status_col = DIAL_VALID_COLOR if in_range else DIAL_INVALID_COLOR
	elif active and _aiming:
		status = "SWEEPING %d%%" % roundi(_direction * 100.0)
		status_col = TRIM_COLOR
	elif active:
		status = "HOLD TO SWEEP THE DIAL"
		status_col = TRIM_COLOR
	_draw_right(font, DIAL_TEXT_RIGHT, READOUT_Y, status, READOUT_SIZE, status_col)


func _draw_center(font: Font, center_x: float, y: float, text: String, size_px: int, color: Color) -> void:
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(center_x - text_w * 0.5, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _draw_right(font: Font, right_x: float, y: float, text: String, size_px: int, color: Color) -> void:
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(right_x - text_w, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
