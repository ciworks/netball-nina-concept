extends Node
## Temporary scaffolding - delete once the run cycle is wired.
##
## Prints the exact layout of the imported run strip: image size, background
## colour, and where the drawn figure pixels sit per column, per row and per
## sixth of the sheet. The frame regions for the SpriteFrames resource are
## computed from that, instead of guessed.
##
## Run res://tools/inspect_run_sheet.tscn once and read the Output panel.

const TARGET := "res://images/img-0d8a1a0a-c548-4c31-8c70-82f54acda16b-1789240073028-0_1789240073029_z5988dez.png"

const BANDS := 6
const ALPHA_CUTOFF := 0.05
const COLOR_TOLERANCE := 0.22

var _img: Image
var _w := 0
var _h := 0
var _bg := Color(0, 0, 0, 0)
var _alpha_bg := true


func _ready() -> void:
	_run()
	get_tree().quit()


func _run() -> void:
	var tex = load(TARGET)
	if tex == null:
		print("RS_LOAD_FAIL")
		return
	_img = tex.get_image()
	if _img == null:
		print("RS_IMAGE_FAIL")
		return
	_img.convert(Image.FORMAT_RGBA8)
	_w = _img.get_width()
	_h = _img.get_height()
	_bg = _img.get_pixel(0, 0)
	_alpha_bg = _bg.a < 0.5

	print("RS_SIZE=%dx%d" % [_w, _h])
	print("RS_BG=%s alpha_background=%s" % [_bg, _alpha_bg])
	print("RS_SAMPLES=%s %s %s" % [
		_img.get_pixel(0, 0),
		_img.get_pixel(_w - 1, 0),
		_img.get_pixel(int(_w / 2.0), _h - 1),
	])

	_print_column_runs()
	_print_row_runs()
	_print_bands()


func _is_ink(x: int, y: int) -> bool:
	var c := _img.get_pixel(x, y)
	if _alpha_bg:
		return c.a > ALPHA_CUTOFF
	var d := absf(c.r - _bg.r) + absf(c.g - _bg.g) + absf(c.b - _bg.b)
	return d > COLOR_TOLERANCE


func _ink_columns() -> PackedByteArray:
	var cols := PackedByteArray()
	cols.resize(_w)
	for x in _w:
		var hit := 0
		for y in _h:
			if _is_ink(x, y):
				hit = 1
				break
		cols[x] = hit
	return cols


func _ink_rows() -> PackedByteArray:
	var rows := PackedByteArray()
	rows.resize(_h)
	for y in _h:
		var hit := 0
		for x in _w:
			if _is_ink(x, y):
				hit = 1
				break
		rows[y] = hit
	return rows


func _print_runs(label: String, flags: PackedByteArray) -> void:
	var parts := PackedStringArray()
	var start := 0
	var current := flags[0]
	for i in range(1, flags.size() + 1):
		var value := current
		if i < flags.size():
			value = flags[i]
		if value != current or i == flags.size():
			var tag := "I" if current == 1 else "E"
			parts.append("%s:%d-%d" % [tag, start, i - 1])
			start = i
			current = value
	print("RS_%s=%s" % [label, ",".join(parts)])


func _print_column_runs() -> void:
	_print_runs("COL", _ink_columns())


func _print_row_runs() -> void:
	_print_runs("ROW", _ink_rows())


func _print_bands() -> void:
	var band_w := int(float(_w) / float(BANDS))
	for i in BANDS:
		var x0 := i * band_w
		var x1 := x0 + band_w - 1
		if i == BANDS - 1:
			x1 = _w - 1
		var min_x := -1
		var max_x := -1
		var min_y := -1
		var max_y := -1
		var count := 0
		for x in range(x0, x1 + 1):
			for y in _h:
				if _is_ink(x, y):
					count += 1
					if min_x < 0 or x < min_x:
						min_x = x
					if x > max_x:
						max_x = x
					if min_y < 0 or y < min_y:
						min_y = y
					if y > max_y:
						max_y = y
		if min_x < 0:
			print("RS_BAND_%d=x%d-%d EMPTY" % [i, x0, x1])
			continue
		var cx := (float(min_x) + float(max_x)) * 0.5
		print("RS_BAND_%d=x%d-%d ink=%d bbox=(%d,%d)-(%d,%d) cx=%.1f cy=%.1f feet=%d" % [
			i, x0, x1, count, min_x, min_y, max_x, max_y, cx,
			(float(min_y) + float(max_y)) * 0.5, max_y,
		])
