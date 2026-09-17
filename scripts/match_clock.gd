extends Control
class_name MatchClock
## The match clock: white seven-segment digits on a black panel, read as an LCD
## countdown at the top centre of the HUD.
##
## It is a display and nothing else. Main owns the match time and hands it the
## seconds left through set_seconds(); the digits are drawn from that one value,
## so the readout can never disagree with the clock Main is running.
##
## The digits are drawn segment by segment rather than set in a font: the LCD
## look is the one thing a default font cannot give, and a seven-segment glyph is
## a handful of chamfered polygons. The segment layout is the classic one:
##
##    a
##   f b
##    g
##   e c
##    d
##
## Every measurement below is in pixels and the panel is sized from them, so
## retuning the readout means changing these constants and nothing else.


## One digit cell, and the thickness of a segment inside it. A segment tapers to
## a mitre at both ends, which is what lets two of them meet cleanly at a corner
## of the cell instead of overlapping into a blob.
const DIGIT_W := 34.0
const DIGIT_H := 46.0
const SEG_THICK := 10.0

## Space between two glyphs, and the width given to the colon between the minutes
## and the seconds.
const GLYPH_GAP := 9.0
const COLON_W := 12.0

## Black margin between the digits and the panel edge. The panel is the dark
## backing the white segments are read against, so it is wider than the digits on
## every side.
const PAD_X := 16.0
const PAD_Y := 10.0

const PANEL_COLOR := Color(0.015, 0.02, 0.025, 0.94)
const SEG_COLOR := Color(1.0, 1.0, 1.0, 1.0)

## Full panel height. A container can reserve the right space for the clock from
## this without measuring the control first.
const PANEL_H := DIGIT_H + PAD_Y * 2.0

## Which of the seven segments each digit lights, in the order a, b, c, d, e, f,
## g. The segments left dark are what make 1, 2, 5 and 7 read as themselves.
const DIGIT_SEGMENTS := {
	0: [true, true, true, true, true, true, false],
	1: [false, true, true, false, false, false, false],
	2: [true, true, false, true, true, false, true],
	3: [true, true, true, true, false, false, true],
	4: [false, true, true, false, false, true, true],
	5: [true, false, true, true, false, true, true],
	6: [true, false, true, true, true, true, true],
	7: [true, true, true, false, false, false, false],
	8: [true, true, true, true, true, true, true],
	9: [true, true, true, true, false, true, true],
}

## The readout as it is drawn. Kept as the formatted text rather than the raw
## seconds so a redraw only happens when a digit actually changes.
var _text := "00:00"
var _panel: StyleBoxFlat


func _ready() -> void:
	# Part of the HUD, so it must never swallow a drag aimed at the court.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = StyleBoxFlat.new()
	_panel.bg_color = PANEL_COLOR
	_panel.set_corner_radius_all(10)
	custom_minimum_size = Vector2(_text_width() + PAD_X * 2.0, PANEL_H)


## The time left, in seconds. Seconds are counted up, so a 30 second game opens on
## 00:30 and the readout only reaches 00:00 when the clock is genuinely out of
## time - it never shows a second the game has not got.
func set_seconds(seconds: float) -> void:
	var text := _format(seconds)
	if text == _text:
		return
	_text = text
	queue_redraw()


func _format(seconds: float) -> String:
	var total := int(ceil(maxf(seconds, 0.0)))
	return "%02d:%02d" % [floori(float(total) / 60.0), total % 60]


func _text_width() -> float:
	var w := 0.0
	for i in _text.length():
		if i > 0:
			w += GLYPH_GAP
		w += COLON_W if _text[i] == ":" else DIGIT_W
	return w


## The top of the digit box. The panel is normally one digit tall with PAD_Y above
## and below it, but if a container hands the control more height than that the
## digits stay centred rather than riding up to the top edge.
func _digit_top() -> float:
	return (size.y - DIGIT_H) * 0.5


func _draw() -> void:
	if _panel != null:
		draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var oy := _digit_top()
	var x := PAD_X
	for i in _text.length():
		var ch := _text[i]
		if ch == ":":
			_draw_colon(x, oy)
			x += COLON_W
		elif ch.is_valid_int():
			_draw_digit(ch.to_int(), x, oy)
			x += DIGIT_W
		if i < _text.length() - 1:
			x += GLYPH_GAP


## The colon between the minutes and the seconds: two small square dots, one in
## each half of the digit height.
func _draw_colon(ox: float, oy: float) -> void:
	var side := SEG_THICK * 0.8
	var cx := ox + COLON_W * 0.5
	var y0 := oy + DIGIT_H * 0.3
	var y1 := oy + DIGIT_H * 0.7
	draw_rect(Rect2(cx - side * 0.5, y0 - side * 0.5, side, side), SEG_COLOR)
	draw_rect(Rect2(cx - side * 0.5, y1 - side * 0.5, side, side), SEG_COLOR)


## One digit, drawn from the seven segment positions. The segment ends are inset
## by half a segment so the mitre tips meet at the corners of the cell.
func _draw_digit(value: int, ox: float, oy: float) -> void:
	if not DIGIT_SEGMENTS.has(value):
		return
	var seg: Array = DIGIT_SEGMENTS[value]
	var t := SEG_THICK * 0.5
	var x_l := ox + t
	var x_r := ox + DIGIT_W - t
	var y_t := oy + t
	var y_m := oy + DIGIT_H * 0.5
	var y_b := oy + DIGIT_H - t
	if seg[0]:
		draw_colored_polygon(_segment_h(y_t, x_l, x_r, t), SEG_COLOR)
	if seg[1]:
		draw_colored_polygon(_segment_v(x_r, y_t, y_m, t), SEG_COLOR)
	if seg[2]:
		draw_colored_polygon(_segment_v(x_r, y_m, y_b, t), SEG_COLOR)
	if seg[3]:
		draw_colored_polygon(_segment_h(y_b, x_l, x_r, t), SEG_COLOR)
	if seg[4]:
		draw_colored_polygon(_segment_v(x_l, y_m, y_b, t), SEG_COLOR)
	if seg[5]:
		draw_colored_polygon(_segment_v(x_l, y_t, y_m, t), SEG_COLOR)
	if seg[6]:
		draw_colored_polygon(_segment_h(y_m, x_l, x_r, t), SEG_COLOR)


## A horizontal segment: a slab centred on y, running x0 to x1, t thick each side
## of its centre line, with both ends drawn to a point. That point is what mitres
## into a vertical segment at a corner of the cell.
func _segment_h(y: float, x0: float, x1: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0 + t, y - t),
		Vector2(x1 - t, y - t),
		Vector2(x1, y),
		Vector2(x1 - t, y + t),
		Vector2(x0 + t, y + t),
		Vector2(x0, y),
	])


## The vertical twin of _segment_h.
func _segment_v(x: float, y0: float, y1: float, t: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, y0),
		Vector2(x + t, y0 + t),
		Vector2(x + t, y1 - t),
		Vector2(x, y1),
		Vector2(x - t, y1 - t),
		Vector2(x - t, y0 + t),
	])
