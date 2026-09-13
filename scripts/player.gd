class_name PlayerToken
extends AnimatedSprite2D
## The player character token for the route prototype.
##
## Passive by design: Main owns position and gameplay state. The token plays
## the animations stored in res://images/player_frames.tres and draws a soft
## ground shadow plus the debug coordinate label.
##
## Frames are added in the SpriteFrames resource, not here: open
## res://images/player_frames.tres, drop more frames into "idle" (or fill the
## empty "move" animation) and the character picks them up. Whatever the frame
## size, the character is scaled to a fixed height relative to one court cell.


## Animation played at rest.
const ANIM_IDLE := "idle"
## Animation played while Main walks the route. Falls back to idle while it has
## no frames yet.
const ANIM_MOVE := "move"

## How tall the character stands, measured in court cells.
const CELL_FILL := 1.2

## Cell height assumed until Main reports the real court layout.
const DEFAULT_CELL_HEIGHT := 64.0

## Logical token radius in pixels. Main writes this on every layout and uses it
## for the touch area, the ball size and the floor highlight.
var radius := 16.0

var label := "Player (5,5)"
var pulse := false
var moving := false

var _phase := 0.0
var _cell_height := DEFAULT_CELL_HEIGHT
var _frame_height := 0.0


func _ready() -> void:
	centered = true
	# The run cycle is smooth painted art, not pixel art, so filter it linearly.
	# Switch this back to TEXTURE_FILTER_NEAREST if the frames go pixel-art again.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_measure_frames()
	_apply_scale()
	_play_if_available(ANIM_IDLE)


## Main calls this on every court layout so the character keeps the same height
## relative to a cell when the viewport resizes.
func set_cell_height(value: float) -> void:
	if value > 0.0:
		_cell_height = value
		_apply_scale()


func set_label(text: String) -> void:
	label = text
	queue_redraw()


func set_pulse(value: bool) -> void:
	pulse = value
	moving = false
	_play_if_available(ANIM_IDLE)
	queue_redraw()


func set_moving(value: bool) -> void:
	moving = value
	pulse = false
	_play_if_available(ANIM_MOVE if moving else ANIM_IDLE)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	if pulse or moving:
		queue_redraw()


## Tallest frame across every animation, so the scale stays stable when the
## animations switch.
func _measure_frames() -> void:
	_frame_height = 0.0
	if sprite_frames == null:
		return
	for anim_name in sprite_frames.get_animation_names():
		for i in range(sprite_frames.get_frame_count(anim_name)):
			var tex: Texture2D = sprite_frames.get_frame_texture(anim_name, i)
			if tex != null:
				_frame_height = maxf(_frame_height, float(tex.get_height()))


func _apply_scale() -> void:
	if _frame_height <= 0.0:
		return
	scale = Vector2.ONE * (_cell_height * CELL_FILL / _frame_height)


func _has_frames(anim_name: String) -> bool:
	return (
		sprite_frames != null
		and sprite_frames.has_animation(anim_name)
		and sprite_frames.get_frame_count(anim_name) > 0
	)


func _play_if_available(anim_name: String) -> void:
	if _has_frames(anim_name):
		play(anim_name)


func _draw() -> void:
	# The sprite itself is drawn through the node scale, so undo that scale for
	# the shadow and the label to keep them at their true size.
	var s := maxf(absf(scale.x), 0.001)
	# Soft ground shadow tucked under the character.
	var shadow_r := maxf(radius, 12.0) * 0.95
	draw_set_transform(Vector2(0.0, radius * 0.7), 0.0, Vector2(1.0, 0.5) / s)
	draw_circle(Vector2.ZERO, shadow_r, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / s)
	if moving:
		var move_ring := radius + 6.0 + sin(_phase * 9.0) * 2.0
		draw_arc(Vector2.ZERO, move_ring, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 2.0, true)
	# Coordinate label under the token.
	var font := ThemeDB.fallback_font
	var label_pos := Vector2(-70.0, radius + 24.0)
	draw_string(font, label_pos + Vector2(0, 1), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color(0, 0, 0, 0.35))
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color(1, 1, 1, 0.95))
