extends Node
## Temporary scaffolding - verifies the run-cycle wiring without opening the game.
##
## Loads the player's SpriteFrames resource and the main scene, then reports the
## animations, frame counts, frame sizes and atlas regions it actually found.
## Run res://tools/verify_run_anim.tscn once and read the Output panel.

const FRAMES_PATH := "res://images/player_frames.tres"
const SCENE_PATH := "res://main.tscn"
const EXPECTED_ANIMS: Array[String] = ["idle", "move", "run"]


func _ready() -> void:
	_check_frames()
	_check_scene()
	get_tree().quit()


func _check_frames() -> void:
	var frames: SpriteFrames = load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		print("VA_FRAMES=LOAD_FAIL")
		return
	print("VA_FRAMES=ok")
	var names: PackedStringArray = frames.get_animation_names()
	print("VA_ANIMS=%s" % ",".join(names))
	for anim in EXPECTED_ANIMS:
		if not frames.has_animation(anim):
			print("VA_ANIM_%s=MISSING" % anim)
			continue
		var count: int = frames.get_frame_count(anim)
		var sizes := PackedStringArray()
		var nulls := 0
		for i in count:
			var tex: Texture2D = frames.get_frame_texture(anim, i)
			if tex == null:
				nulls += 1
				sizes.append("null")
				continue
			sizes.append("%dx%d" % [tex.get_width(), tex.get_height()])
		var loop: bool = frames.get_animation_loop(anim)
		var speed: float = frames.get_animation_speed(anim)
		var frames_ok := nulls == 0 and count > 0
		print("VA_ANIM_%s frames=%d loop=%s speed=%.1f nulls=%d sizes=%s frames_ok=%s" % [
			anim, count, loop, speed, nulls, ",".join(sizes), frames_ok,
		])


func _check_scene() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		print("VA_SCENE=LOAD_FAIL")
		return
	print("VA_SCENE=ok can_instance=%s" % packed.can_instantiate())
	var root: Node = packed.instantiate()
	var sprite := root.get_node_or_null("Player") as AnimatedSprite2D
	if sprite == null:
		print("VA_PLAYER=NOT_FOUND")
		root.free()
		return
	var frames: SpriteFrames = sprite.sprite_frames
	var bound := frames != null
	print("VA_PLAYER z_index=%d frames_bound=%s position=%s scale=%s" % [
		sprite.z_index, bound, sprite.position, sprite.scale,
	])
	if bound:
		print("VA_PLAYER_ANIMS=%s" % ",".join(frames.get_animation_names()))
		sprite.play("move")
		print("VA_PLAYER_PLAYING anim=%s frame=%d move_frames=%d speed=%.1f" % [
			sprite.animation, sprite.frame,
			frames.get_frame_count("move"), frames.get_animation_speed("move"),
		])
	root.free()
