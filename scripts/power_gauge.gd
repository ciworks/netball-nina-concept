class_name PowerGauge
extends Control
## Floating shot-power meter, shown while the token is holding the ball.
##
## The meter is a classic power bar: a needle runs the range, and a brighter band
## marks the range that would send an accurate shot at the post from where the
## token is standing. The band's position follows the distance from the token to
## the goal post - stood under the post wants little power, a shot from the far
## corner wants nearly all of it - and it narrows as that distance grows, so the
## range the player has to land in is a finer ask from further out.
##
## This is the display half of the mechanic only. Shooting does not exist in the
## prototype yet, so nothing consumes power() and no shot is fired: the player
## holds the meter down to charge the needle and lets go to lock in the value
## they selected. When a shot is added, the locked value is the power it was
## given - ask in_accuracy_band() (or compare power() against required_range())
## to decide whether the shot was accurate.
##
## The gauge never takes input. It floats over the middle of the court, and a
## Control that stopped touches there would swallow the drag strokes drawn across
## the screen (see the UI mouse filter rule in AGENTS.md).

## The whole floating panel, in pixels. Wide enough to read as a meter on a
## phone stretched to the 1280x720 base.
const GAUGE_SIZE := Vector2(460.0, 104.0)

## The track the needle runs along, in this control's local space.
const TRACK_MARGIN := 16.0
const TRACK_TOP := 30.0
const TRACK_HEIGHT := 34.0
const TRACK_INSET := 7.0
const TRACK_RADIUS := 9
const BAND_RADIUS := 6
const TICK_COUNT := 10

## Distance from the token to the post, in court cells, that the meter maps
## across its full range: MIN is a token stood right under the post, MAX is the
## longest shot this court allows (corner to corner is about 14.1 cells).
const MIN_DISTANCE_CELLS := 1.0
const MAX_DISTANCE_CELLS := 14.0

## Where the required range sits on the track, as a fraction of full power. A
## close shot wants little power and a long one wants nearly all of it.
const BAND_CENTER_NEAR := 0.18
const BAND_CENTER_FAR := 0.86

## Half-width of the required range: the tolerance the player has to stay
## inside. It tightens with distance, so a shot from the far end of the court is
## a finer ask than one from under the post.
const BAND_HALF_NEAR := 0.10
const BAND_HALF_FAR := 0.04

## How fast the needle climbs while the player holds it down, in power units per
## second: a full-power hold takes just under a second.
const CHARGE_SPEED := 1.15

const PANEL_COLOR := Color(0.03, 0.10, 0.14, 0.74)
const TRACK_COLOR := Color(0.05, 0.11, 0.16, 0.92)
const TRACK_EDGE := Color(1.0, 1.0, 1.0, 0.20)
const FILL_COLOR := Color(0.20, 0.55, 0.72, 0.85)
const BAND_COLOR := Color(0.98, 0.78, 0.20, 0.80)
const BAND_IN_COLOR := Color(0.36, 0.95, 0.55, 0.92)
const NEEDLE_COLOR := Color(1.0, 1.0, 1.0, 0.97)
const TICK_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const TEXT_COLOR := Color(0.92, 1.0, 1.0, 0.96)
const TEXT_DIM := Color(0.80, 0.90, 0.94, 0.72)

## Distance the meter is currently reading, in court cells.
var _distance := MIN_DISTANCE_CELLS
## The band of meter positions that would be an accurate shot at _distance.
var _band_lo := 0.0
var _band_hi := 1.0
## Current needle position, 0..1 across the track.
var _power := 0.0
## True while the player is holding the meter down: the needle only climbs then.
var _charging := false
## True once the player has released on a value: the needle is frozen on the
## selection until the next hold starts.
var _locked := false
var _phase := 0.0

# Cached styleboxes - the panel, the track, the power fill and the required range
# band - so drawing allocates nothing per frame.
var _panel_sb: StyleBoxFlat
var _track_sb: StyleBoxFlat
var _fill_sb: StyleBoxFlat
var _band_sb: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = GAUGE_SIZE
	# The gauge hangs over the court, so it must never consume a touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_sb = _make_box(PANEL_COLOR, 14)
	_track_sb = _make_box(TRACK_COLOR, TRACK_RADIUS)
	_track_sb.border_color = TRACK_EDGE
	_track_sb.set_border_width_all(1)
	_fill_sb = _make_box(FILL_COLOR, TRACK_RADIUS)
	_band_sb = _make_box(BAND_COLOR, BAND_RADIUS)
	_recompute_band()


func _process(delta: float) -> void:
	if not visible:
		return
	_phase += delta
	# Hold to charge. The needle climbs only while the player is holding the meter
	# down, and letting go locks it. Nothing consumes the value yet - the shot
	# that will is not built - so the lock is what makes a selection visible, and
	# the required band stays drawn beside it so the value can be aimed at.
	if _charging and not _locked:
		_power = minf(_power + CHARGE_SPEED * delta, 1.0)
	queue_redraw()


## Shows or hides the meter. Every possession starts its sweep from zero, so the
## needle always reads the same way when the ball comes to the player.
func set_active(on: bool) -> void:
	visible = on
	if on:
		_power = 0.0
		_charging = false
		_locked = false
		_phase = 0.0
	queue_redraw()


## The player pressed down on the meter, so the needle starts a fresh climb from
## zero: every hold reads the same way.
func begin_charge() -> void:
	_charging = true
	_locked = false
	_power = 0.0
	queue_redraw()


## The player let go, so the value the needle reached is the one they selected.
## It stays put until the next hold. This is the moment a shot direction meter
## belongs on screen (see main.gd).
func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	_locked = true
	queue_redraw()


## True once the player has released on a value, i.e. the selection is made.
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


## Current needle position, 0..1. A future shot reads this as the power it was
## given.
func power() -> float:
	return _power


## The band of positions that would be an accurate shot at the current distance,
## as a (low, high) pair in 0..1.
func required_range() -> Vector2:
	return Vector2(_band_lo, _band_hi)


## True while the needle is inside the required range: the accurate shot the
## meter is asking for. Nothing acts on this yet - it brightens the band so the
## requirement can be read.
func in_accuracy_band() -> bool:
	return _power >= _band_lo and _power <= _band_hi


## Drives the needle from outside, for a shooting move that drives the value
## itself instead of the player's hold.
func set_power(value: float) -> void:
	_power = clampf(value, 0.0, 1.0)
	queue_redraw()


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
	var w := GAUGE_SIZE.x
	draw_style_box(_panel_sb, Rect2(Vector2.ZERO, GAUGE_SIZE))

	var track := Rect2(Vector2(TRACK_MARGIN, TRACK_TOP),
			Vector2(w - TRACK_MARGIN * 2.0, TRACK_HEIGHT))
	var span_x := track.position.x + TRACK_INSET
	var span_w := maxf(track.size.x - TRACK_INSET * 2.0, 1.0)
	var needle_x := span_x + span_w * _power
	var in_band := in_accuracy_band()

	# Title row: what the meter is, and the distance it is reading from.
	draw_string(font, Vector2(TRACK_MARGIN, 21.0), "SHOT POWER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	_draw_right(font, w - TRACK_MARGIN, 21.0, "POST %.1f CELLS" % _distance, 13, TEXT_DIM)

	# Track, the power generated so far, then a light scale over both.
	draw_style_box(_track_sb, track)
	var fill_w := clampf(needle_x - track.position.x, 0.0, track.size.x)
	if fill_w > 1.0:
		draw_style_box(_fill_sb, Rect2(track.position, Vector2(fill_w, track.size.y)))
	var tick_cy := track.position.y + track.size.y * 0.5
	for i in range(1, TICK_COUNT):
		var tx := span_x + span_w * (float(i) / float(TICK_COUNT))
		draw_line(Vector2(tx, tick_cy - 5.0), Vector2(tx, tick_cy + 5.0), TICK_COLOR, 1.0, true)

	# The required range for this distance, drawn over the fill so it stays
	# readable wherever the needle happens to be. It turns green and glows when
	# the needle is inside it.
	var band_x0 := span_x + span_w * _band_lo
	var band_x1 := span_x + span_w * _band_hi
	_band_sb.bg_color = BAND_IN_COLOR if in_band else BAND_COLOR
	draw_style_box(_band_sb, Rect2(
			Vector2(band_x0, track.position.y + 2.0),
			Vector2(maxf(band_x1 - band_x0, 4.0), track.size.y - 4.0)))
	if in_band:
		var glow := 0.5 + 0.5 * sin(_phase * 8.0)
		draw_circle(Vector2(needle_x, tick_cy), 9.0 + glow * 2.5,
				Color(BAND_IN_COLOR.r, BAND_IN_COLOR.g, BAND_IN_COLOR.b, 0.16 + 0.12 * glow))

	# The needle, with a soft drop shadow so it reads over the band.
	draw_rect(Rect2(Vector2(needle_x - 1.0, track.position.y - 3.0),
			Vector2(4.0, track.size.y + 10.0)), Color(0, 0, 0, 0.35), true)
	draw_rect(Rect2(Vector2(needle_x - 2.0, track.position.y - 5.0),
			Vector2(4.0, track.size.y + 10.0)), NEEDLE_COLOR, true)

	# Readout row: what the needle is doing and what the meter is asking for.
	var base_y := GAUGE_SIZE.y - 13.0
	var lo_pct := roundi(_band_lo * 100.0)
	var hi_pct := roundi(_band_hi * 100.0)
	var power_txt := "POWER %d%%" % roundi(_power * 100.0)
	if _locked:
		power_txt = "LOCKED AT %d%%" % roundi(_power * 100.0)
	draw_string(font, Vector2(TRACK_MARGIN, base_y), power_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
	_draw_center(font, w * 0.5, base_y, "REQUIRED %d-%d%%" % [lo_pct, hi_pct], 14, TEXT_DIM)
	_draw_right(font, w - TRACK_MARGIN, base_y,
			"IN RANGE" if in_band else "OUT OF RANGE", 14,
			BAND_IN_COLOR if in_band else TEXT_DIM)


func _draw_center(font: Font, center_x: float, y: float, text: String, size_px: int, color: Color) -> void:
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(center_x - text_w * 0.5, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _draw_right(font: Font, right_x: float, y: float, text: String, size_px: int, color: Color) -> void:
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(right_x - text_w, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
