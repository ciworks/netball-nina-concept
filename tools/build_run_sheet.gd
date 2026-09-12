extends Node
## Temporary scaffolding - builds the run-cycle strip from the imported art.
##
## Loads the raw sheet, keys out its flat magenta backdrop, splits the six drawn
## figures apart and repacks them into one strip whose six cells are exactly the
## same size with a shared baseline. Uniform cells are what let an
## AnimatedSprite2D play the frames without the character jittering sideways.
##
## Run res://tools/build_run_sheet.tscn once and read the Output panel.

const SOURCE := "res://images/img-0d8a1a0a-c548-4c31-8c70-82f54acda16b-1789240073028-0_1789240073029_z5988dez.png"
const OUTPUT := "res://images/run_back_3q_right.png"

const EXPECTED_FIGURES := 6
## Colour distance from the backdrop that is treated as fully transparent.
const KEY_INNER := 0.08
## Colour distance from the backdrop that is treated as fully opaque.
const KEY_OUTER := 0.30
## Alpha at or above this counts as character pixel.
const INK_ALPHA := 0.35
## Ink pixels a column needs before it counts as occupied by a figure.
const MIN_COLUMN_INK := 3
## Empty columns needed to separate two figures.
const FIGURE_GAP := 3
## Transparent margin kept above and below the figures.
const BAND_MARGIN := 12
## Transparent margin kept at the left and right of every cell.
const SIDE_PAD := 6
## Top fraction of a figure used to find the axis of its head.
const HEAD_BAND := 0.18

var _img: Image
var _w := 0
var _h := 0
var _bg := Color(0, 0, 0, 0)


func _ready() -> void:
	_run()
	get_tree().quit()


func _run() -> void:
	var tex = load(SOURCE)
	if tex == null:
		print("RB_LOAD_FAIL")
		return
	_img = tex.get_image()
	if _img == null:
		print("RB_IMAGE_FAIL")
		return
	_img.convert(Image.FORMAT_RGBA8)
	_w = _img.get_width()
	_h = _img.get_height()
	_bg = _img.get_pixel(0, 0)
	print("RB_SOURCE=%dx%d bg=%s" % [_w, _h, _bg])

	_key_background()

	var rows := _ink_bounds_rows()
	if rows.is_empty():
		print("RB_NO_INK")
		return
	var band_y0 := maxi(0, int(rows[0]) - BAND_MARGIN)
	var band_y1 := mini(_h - 1, int(rows[1]) + BAND_MARGIN)
	var cell_h := band_y1 - band_y0 + 1

	var runs := _figure_runs()
	print("RB_FIGURES=%d" % runs.size())
	if runs.size() != EXPECTED_FIGURES:
		print("RB_ABORT_FIGURE_COUNT")
		return

	var heads := PackedFloat32Array()
	var half := 0.0
	for run in runs:
		var box := _ink_bounds_columns(run[0], run[1])
		if box.is_empty():
			print("RB_EMPTY_FIGURE=%d-%d" % [run[0], run[1]])
			return
		var head_x := _head_axis(run[0], run[1], box[1], box[3])
		heads.append(head_x)
		half = maxf(half, maxf(head_x - float(box[0]), float(box[2]) - head_x))
		print("RB_FIG=%d x=%d-%d y=%d-%d head_x=%.1f" % [
			heads.size() - 1, box[0], box[2], box[1], box[3], head_x,
		])

	var cell_w := int(ceil(half)) * 2 + SIDE_PAD * 2
	var total_w := cell_w * runs.size()
	print("RB_CELL=%dx%d TOTAL=%dx%d" % [cell_w, cell_h, total_w, cell_h])

	var out := Image.create(total_w, cell_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))

	var clipped := 0
	for i in runs.size():
		var run = runs[i]
		var centre := float(i * cell_w + int(cell_w / 2.0))
		var shift := int(round(centre - heads[i]))
		var pasted := 0
		for sx in range(int(run[0]), int(run[1]) + 1):
			var dx := sx + shift
			if dx < i * cell_w or dx >= (i + 1) * cell_w:
				clipped += 1
				continue
			for sy in range(band_y0, band_y1 + 1):
				var c := _img.get_pixel(sx, sy)
				if c.a > 0.0:
					out.set_pixel(dx, sy - band_y0, c)
					pasted += 1
		print("RB_CELL_%d run=%d-%d pasted=%d" % [i, run[0], run[1], pasted])

	print("RB_CLIPPED=%d" % clipped)
	_print_cell_stats(out, cell_w, cell_h, runs.size())

	var err := out.save_png(OUTPUT)
	print("RB_SAVE=%d path=%s" % [err, OUTPUT])


## Turns the flat backdrop into transparency, un-blending the backdrop colour
## out of the soft edge pixels so no pink fringe is left around the outline.
func _key_background() -> void:
	for x in _w:
		for y in _h:
			var c := _img.get_pixel(x, y)
			var d := maxf(
				maxf(absf(c.r - _bg.r), absf(c.g - _bg.g)),
				absf(c.b - _bg.b)
			)
			var a := clampf((d - KEY_INNER) / (KEY_OUTER - KEY_INNER), 0.0, 1.0)
			if a <= 0.0:
				_img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif a < 1.0:
				var s := 1.0 - a
				_img.set_pixel(x, y, Color(
					clampf((c.r - _bg.r * s) / a, 0.0, 1.0),
					clampf((c.g - _bg.g * s) / a, 0.0, 1.0),
					clampf((c.b - _bg.b * s) / a, 0.0, 1.0),
					a
				))
			else:
				_img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))


func _column_ink(x: int) -> int:
	var count := 0
	for y in _h:
		if _img.get_pixel(x, y).a >= INK_ALPHA:
			count += 1
	return count


## Left and right edge of the drawn content, plus its top and bottom row, as a
## [left, top, right, bottom] array. Empty when nothing is drawn.
func _ink_bounds_columns(x0: int, x1: int) -> Array:
	var left := -1
	var right := -1
	var top := -1
	var bottom := -1
	for x in range(x0, x1 + 1):
		for y in _h:
			if _img.get_pixel(x, y).a >= INK_ALPHA:
				if left < 0:
					left = x
				right = x
				if top < 0 or y < top:
					top = y
				if y > bottom:
					bottom = y
	if left < 0:
		return []
	return [left, top, right, bottom]


func _ink_bounds_rows() -> Array:
	var top := -1
	var bottom := -1
	for y in _h:
		for x in _w:
			if _img.get_pixel(x, y).a >= INK_ALPHA:
				if top < 0:
					top = y
				bottom = y
				break
	if top < 0:
		return []
	return [top, bottom]


## Column ranges, one per drawn figure, split on runs of empty columns.
func _figure_runs() -> Array:
	var runs := []
	var start := -1
	var last_ink := -1
	var gap := 0
	for x in _w:
		var occupied := _column_ink(x) >= MIN_COLUMN_INK
		if occupied:
			if start < 0:
				start = x
			last_ink = x
			gap = 0
		elif start >= 0:
			gap += 1
			if gap >= FIGURE_GAP:
				runs.append([start, last_ink])
				start = -1
				gap = 0
	if start >= 0:
		runs.append([start, last_ink])
	return runs


## Average x of the head band, used as the stable axis to centre a figure on so
## that swinging arms and legs do not push the body sideways between frames.
func _head_axis(x0: int, x1: int, y0: int, y1: int) -> float:
	var limit := float(y0) + maxf(4.0, float(y1 - y0) * HEAD_BAND)
	var sum := 0.0
	var count := 0
	for x in range(x0, x1 + 1):
		for y in range(y0, mini(int(limit), y1) + 1):
			if _img.get_pixel(x, y).a >= INK_ALPHA:
				sum += float(x)
				count += 1
	if count == 0:
		return float(x0 + x1) * 0.5
	return sum / float(count)


func _print_cell_stats(img: Image, cell_w: int, cell_h: int, cells: int) -> void:
	for i in cells:
		var x0 := i * cell_w
		var left := -1
		var right := -1
		var top := -1
		var bottom := -1
		var count := 0
		for x in range(x0, x0 + cell_w):
			for y in cell_h:
				if img.get_pixel(x, y).a >= INK_ALPHA:
					count += 1
					if left < 0 or x < left:
						left = x - x0
					if x - x0 > right:
						right = x - x0
					if top < 0 or y < top:
						top = y
					if y > bottom:
						bottom = y
		print("RB_OUT_%d ink=%d bbox=(%d,%d)-(%d,%d) centre_x=%.1f feet=%d" % [
			i, count, left, top, right, bottom,
			(float(left) + float(right)) * 0.5, bottom,
		])
