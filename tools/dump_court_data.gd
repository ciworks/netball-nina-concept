extends Node
## Temporary scaffolding - delete once main.tscn holds the painted court.
##
## Paints the starting court (11x11 checkerboard floor plus the third lines and
## mid line) through real TileMapLayers so the engine encodes the exact
## PackedByteArray for TileMapLayer.tile_map_data. Those blobs are written to
## res://tools/court_data.txt and then pasted into main.tscn, which is what
## makes the court hand-paintable in the editor instead of generated at runtime.
##
## Run res://tools/dump_court_data.tscn once, then read res://tools/court_data.txt.

const GRID_MAX := 10

const FLOOR_LIGHT := Vector2i(0, 0)
const FLOOR_DARK := Vector2i(1, 0)
const LINE_V := Vector2i(2, 0)
const LINE_H := Vector2i(3, 0)

## Thirds of a 10-unit court fall at 3.33 and 6.67, so they snap to the
## nearest grid columns, 3 and 7. The mid line sits exactly on row 5.
const THIRD_A := 3
const THIRD_B := 7
const MID_ROW := 5


func _ready() -> void:
	var tileset: TileSet = load("res://tiles/court_tileset.tres")
	var atlas_size := Vector2.ZERO
	var tile_count := -1
	if tileset != null and tileset.get_source_count() > 0:
		var src := tileset.get_source(0) as TileSetAtlasSource
		if src != null and src.texture != null:
			atlas_size = src.texture.get_size()
		if src != null:
			tile_count = src.get_tiles_count()
	print("DUMP_TILESET=", tileset != null)
	print("DUMP_ATLAS=", atlas_size)
	print("DUMP_TILE_COUNT=", tile_count)

	var root := Node2D.new()
	root.name = "Dump"

	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Court"
	if tileset != null:
		floor_layer.tile_set = tileset
	for x in range(GRID_MAX + 1):
		for y in range(GRID_MAX + 1):
			var atlas: Vector2i = FLOOR_LIGHT if (x + y) % 2 == 0 else FLOOR_DARK
			floor_layer.set_cell(Vector2i(x, y), 0, atlas)
	root.add_child(floor_layer)
	floor_layer.owner = root

	var markings := TileMapLayer.new()
	markings.name = "CourtMarkings"
	if tileset != null:
		markings.tile_set = tileset
	for y in range(GRID_MAX + 1):
		markings.set_cell(Vector2i(THIRD_A, y), 0, LINE_V)
		markings.set_cell(Vector2i(THIRD_B, y), 0, LINE_V)
	for x in range(GRID_MAX + 1):
		markings.set_cell(Vector2i(x, MID_ROW), 0, LINE_H)
	root.add_child(markings)
	markings.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://tools/dumped_court.tscn")
	print("DUMP_SAVE_ERR=", err)

	var f := FileAccess.open("res://tools/court_data.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("FLOOR=" + var_to_str(floor_layer.tile_map_data))
		f.store_line("MARK=" + var_to_str(markings.tile_map_data))
		f.close()
	print("DUMP_FLOOR_CELLS=", floor_layer.get_used_cells().size())
	print("DUMP_MARK_CELLS=", markings.get_used_cells().size())
	get_tree().quit()
