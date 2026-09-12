class_name CourtBoard
extends TileMapLayer
## Route-highlight overlay for the netball court.
##
## The court itself is hand-painted, not generated: the sand checkerboard lives
## on the "Court" TileMapLayer and the white third/mid line tiles on
## "CourtMarkings", both using res://tiles/court_tileset.tres. They are edited
## directly in the editor's TileMap panel.
##
## This node draws ONLY the route highlight, so the authored court art is never
## rewritten at run time.
##
## The highlight look comes from res://images/court_move_highlight.png, a
## rounded panel: its fill colour and its corner rounding are read off that
## image, so changing the art restyles the highlight. The image carries white in
## its rounded-off corners, so those pixels count as the cut-away background and
## stay transparent, letting the court show through.
##
## Selected cells merge into one shape: a selected panel fills its whole tile,
## but a corner is rounded only where the two sides meeting there are BOTH on
## the outside of the route. A corner that touches another selected cell stays
## square, so a connected route reads as one continuous band with soft turns
## instead of a row of loose squares.
##
## The node transform is set from outside (main.gd) to match the court layers:
## the overlay is a child of CourtRig, which applies the isometric flattening.

const TILE_PX := 32
## One atlas tile per border mask, so the tile index is the mask itself.
const MASK_TILES := 16

const HIGHLIGHT_IMAGE := preload("res://images/court_move_highlight.png")

const CLEAR := Color(0, 0, 0, 0)
## Used only if the highlight image cannot be sampled.
const FALLBACK_FILL := Color(0.08, 0.78, 0.74, 1.0)

const MASK_TOP := 1
const MASK_RIGHT := 2
const MASK_BOTTOM := 4
const MASK_LEFT := 8

var _cell_count := 0
var _highlighted: Array[Vector2i] = []
var _fill_color: Color = FALLBACK_FILL
## Pixel offsets, measured from a tile corner (x right / y down), that the
## highlight image leaves as rounded-off background. Read once from the image's
## top-left corner so the overlay's rounding follows the art instead of a
## hard-coded radius.
var _corner_cut: Array[Vector2i] = []


func _ready() -> void:
	_read_highlight_style()
	_build_tileset()


## Reads the highlight image once: the panel fill colour and the exact set of
## corner pixels the art rounds off. Both fall back to safe defaults if the
## image cannot be sampled.
func _read_highlight_style() -> void:
	_fill_color = FALLBACK_FILL
	_corner_cut.clear()
	if HIGHLIGHT_IMAGE == null:
		return
	var img: Image = HIGHLIGHT_IMAGE.get_image()
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8:
		return
	_fill_color = img.get_pixel(int(w / 2), int(h / 2))
	# The rounded-off corners are the image's background colour. Measure the run
	# along the top row and down the left column, then keep the background pixels
	# inside that corner block - that is the cut shape the art actually uses.
	var run_x := 0
	while run_x < w and _is_background(img.get_pixel(run_x, 0)):
		run_x += 1
	var run_y := 0
	while run_y < h and _is_background(img.get_pixel(0, run_y)):
		run_y += 1
	if run_x <= 0 or run_y <= 0 or run_x * 2 >= w or run_y * 2 >= h:
		return
	for y in run_y:
		for x in run_x:
			if _is_background(img.get_pixel(x, y)):
				_corner_cut.append(Vector2i(x, y))


## True for a pixel that reads as the image's rounded-off background: either
## already transparent, or near-white.
func _is_background(c: Color) -> bool:
	return c.a <= 0.05 or (c.r > 0.85 and c.g > 0.85 and c.b > 0.85)


## Builds a 16-tile atlas at runtime, one tile per border mask (tile index ==
## mask). Each tile is a full highlight panel; only the corners where two
## outside edges meet are cut back, so merged cells read as one band.
func _build_tileset() -> void:
	var image := Image.create_empty(TILE_PX * MASK_TILES, TILE_PX, false, Image.FORMAT_RGBA8)
	image.fill(CLEAR)
	for mask in MASK_TILES:
		_paint_highlight(image, mask * TILE_PX, mask)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	for i in MASK_TILES:
		atlas.create_tile(Vector2i(i, 0))

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_PX, TILE_PX)
	tileset.add_source(atlas, 0)

	tile_set = tileset
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Fills one atlas tile with the highlight colour, then cuts back every corner
## that lies on the outside of the route - that is, a corner where both of its
## meeting sides are exposed - using the corner shape read from the image.
func _paint_highlight(image: Image, x0: int, mask: int) -> void:
	image.fill_rect(Rect2i(x0, 0, TILE_PX, TILE_PX), _fill_color)
	var top := mask & MASK_TOP != 0
	var bottom := mask & MASK_BOTTOM != 0
	var left := mask & MASK_LEFT != 0
	var right := mask & MASK_RIGHT != 0
	if top and left:
		_cut_corner(image, x0, 0, 0, 1, 1)
	if top and right:
		_cut_corner(image, x0, TILE_PX - 1, 0, -1, 1)
	if bottom and left:
		_cut_corner(image, x0, 0, TILE_PX - 1, 1, -1)
	if bottom and right:
		_cut_corner(image, x0, TILE_PX - 1, TILE_PX - 1, -1, -1)


## Clears the image's rounded-corner pixels at the corner located at (cx, cy).
## sx / sy point inward from that corner (+1 from a left or top corner, -1 from
## a right or bottom one), so one corner shape serves all four corners.
func _cut_corner(image: Image, x0: int, cx: int, cy: int, sx: int, sy: int) -> void:
	for off in _corner_cut:
		image.set_pixel(x0 + cx + off.x * sx, cy + off.y * sy, CLEAR)


## Clears the overlay and records the grid size the route is clamped to. The
## court floor is authored tile data now, so this no longer paints anything.
func layout(_origin: Vector2, _cell_px: Vector2, cells: int) -> void:
	_cell_count = cells
	_highlighted.clear()
	clear()


## Marks every route cell (clamped to the grid) as selected. The route from the
## gesture only stores corner points, so each straight segment is expanded into
## every cell it passes through first. Selection state is recomputed for the
## changed panels only: each selected panel is filled, and its border mask says
## which of its sides sit on the outside of the route, so the highlight's corners
## are rounded only at outer turns and shared edges stay clean.
func set_route(cells: Array[Vector2i]) -> void:
	if _cell_count <= 0:
		return
	var target := {}
	for c in _expand_route(cells):
		var cl := Vector2i(clampi(c.x, 0, _cell_count - 1), clampi(c.y, 0, _cell_count - 1))
		target[cl] = true

	var affected := {}
	for cl in _highlighted:
		affected[cl] = true
	for cl in target:
		affected[cl] = true

	for cl in affected:
		# A cell fully surrounded by other route cells has mask 0. It is still
		# part of the highlight, so it keeps the plain, uncut atlas tile instead
		# of being erased - otherwise a filled route would have a hole in it.
		if target.has(cl):
			set_cell(cl, 0, _atlas_for(_border_mask(cl, target)))
		else:
			erase_cell(cl)

	_highlighted.clear()
	for cl in target:
		_highlighted.append(cl)


## Expands a corner-point route into every cell along each straight segment,
## so a run from (2,5) to (8,5) yields (2,5),(3,5),...,(8,5).
func _expand_route(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if cells.is_empty():
		return out
	out.append(cells[0])
	for i in range(1, cells.size()):
		var a := cells[i - 1]
		var b := cells[i]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		if step == Vector2i.ZERO:
			continue
		var cur := a + step
		while true:
			out.append(cur)
			if cur == b:
				break
			cur += step
	return out


## Deselects every route panel, leaving the overlay empty so the painted floor
## shows through again.
func clear_route() -> void:
	for cl in _highlighted:
		erase_cell(cl)
	_highlighted.clear()


## Border sides are only the edges whose neighbor is NOT also selected.
## Out-of-grid neighbors count as unselected, so a path along the court edge
## keeps its border on the outer side.
func _border_mask(cl: Vector2i, selected: Dictionary) -> int:
	var mask := 0
	if not selected.has(Vector2i(cl.x, cl.y - 1)):
		mask |= MASK_TOP
	if not selected.has(Vector2i(cl.x + 1, cl.y)):
		mask |= MASK_RIGHT
	if not selected.has(Vector2i(cl.x, cl.y + 1)):
		mask |= MASK_BOTTOM
	if not selected.has(Vector2i(cl.x - 1, cl.y)):
		mask |= MASK_LEFT
	return mask


## Maps a border mask to its overlay atlas tile (tile index == mask).
func _atlas_for(mask: int) -> Vector2i:
	return Vector2i(mask, 0)
