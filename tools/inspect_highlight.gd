extends Node
## Temporary scaffolding - delete once the highlight tile art is wired in.
##
## Prints the route-highlight reference image as a character map, so the shape
## (rounded corners, border, fill) can be read exactly instead of guessed.
##
## Legend: G = green fill, W = near-white, . = transparent, ? = anything else.
##
## Run res://tools/inspect_highlight.tscn once and read the Output panel.

const TARGET := "res://images/court_move_highlight.png"


func _ready() -> void:
	_inspect()
	get_tree().quit()


func _inspect() -> void:
	var tex = load(TARGET)
	if tex == null:
		print("HL_LOAD_FAIL")
		return
	var img: Image = tex.get_image()
	var w := img.get_size().x
	var h := img.get_size().y
	print("HL_SIZE=", w, "x", h, " fmt=", img.get_format())
	print("HL_CENTER=", img.get_pixel(int(w / 2.0), int(h / 2.0)))
	print("HL_CORNER=", img.get_pixel(0, 0))
	for y in h:
		var row := ""
		for x in w:
			row += _glyph(img.get_pixel(x, y))
		print("HL_ROW_%02d=%s" % [y, row])


func _glyph(c: Color) -> String:
	if c.a <= 0.05:
		return "."
	if c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
		return "W"
	if c.g > c.r and c.g > c.b:
		return "G"
	return "?"
