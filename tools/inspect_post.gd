extends Node
## Temporary scaffolding: prints the geometry of res://images/netball_post.png,
## so the hoop the shot aims at can be placed from the art instead of guessed.
##
## The ring is the only red-dominant thing in the image (the pole and the net are
## grey), so it can be found by colour and reported as fractions of the texture.
## Those fractions are what main.gd's HOOP_* constants come from.
##
## Run res://tools/inspect_post.tscn once and read the Output panel.

const TARGET := "res://images/netball_post.png"
## How red a pixel has to be to count as the ring rather than the grey pole.
const RING_MIN_RED := 0.45
const RING_DOMINANCE := 1.5


func _ready() -> void:
	_inspect()
	get_tree().quit()


func _inspect() -> void:
	var tex = load(TARGET)
	if tex == null:
		print("POST_LOAD_FAIL")
		return
	var img: Image = tex.get_image()
	var w: int = img.get_width()
	var h: int = img.get_height()
	print("POST_SIZE=%dx%d aspect=%.4f" % [w, h, float(w) / float(h)])

	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var rmin_x := w
	var rmin_y := h
	var rmax_x := -1
	var rmax_y := -1
	var rsum := Vector2.ZERO
	var rcount := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.05:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			if c.r > RING_MIN_RED and c.r > c.g * RING_DOMINANCE \
					and c.r > c.b * RING_DOMINANCE:
				rmin_x = mini(rmin_x, x)
				rmin_y = mini(rmin_y, y)
				rmax_x = maxi(rmax_x, x)
				rmax_y = maxi(rmax_y, y)
				rsum += Vector2(float(x), float(y))
				rcount += 1

	if max_x < 0:
		print("POST_ALPHA=empty")
		return
	print("POST_ALPHA_BOUNDS=%d,%d..%d,%d" % [min_x, min_y, max_x, max_y])
	print("POST_ALPHA_FRAC_OF_TEXTURE=w%.4f h%.4f at %.4f,%.4f" % [
		float(max_x - min_x + 1) / float(w),
		float(max_y - min_y + 1) / float(h),
		float(min_x) / float(w),
		float(min_y) / float(h)])

	if rcount == 0:
		print("POST_RING=none")
		return
	var rc := rsum / float(rcount)
	print("POST_RING_BOUNDS=%d,%d..%d,%d size=%dx%d" % [
		rmin_x, rmin_y, rmax_x, rmax_y, rmax_x - rmin_x + 1, rmax_y - rmin_y + 1])
	print("POST_RING_CENTRE_PX=%.2f,%.2f" % [rc.x, rc.y])
	# The two numbers main.gd needs: where the ring's centre sits in the texture,
	# and how far it is off the texture's centre line (the pole's column).
	print("POST_RING_TEXTURE_FRAC=%.4f,%.4f" % [rc.x / float(w), rc.y / float(h)])
	print("POST_RING_X_OFFSET_FRAC_OF_W=%.4f" % ((rc.x - float(w) * 0.5) / float(w)))
	print("POST_RING_ABOVE_TEXTURE_BOTTOM_FRAC=%.4f" % ((float(h) - rc.y) / float(h)))
	print("POST_RING_PIXELS=%d" % rcount)
