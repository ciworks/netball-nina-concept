extends CanvasLayer
## Builds the prototype UI: scenario quick picks, reset, status pill, debug and
## grid toggles, the contextual instruction line, transient feedback, and the
## developer debug panel. The play area stays clear: UI hugs the edges.


var _status: Label
var _instruction: Label
var _feedback: PanelContainer
var _feedback_label: Label
var _debug_panel: PanelContainer
var _debug_label: Label
var _debug_btn: Button
var _grid_btn: Button
var _reset_btn: Button
var _scenario_btns: Array[Button] = []
var _avatar: PlayerAvatar
var _power_gauge: PowerGauge

var _feedback_timer := 0.0
var _rating_label: Label
var _rating_tween: Tween

## Player avatar box, pinned to the top-left corner. The control bar starts clear
## of it so nothing overlaps as the viewport resizes.
const AVATAR_MARGIN := 12.0
const AVATAR_TOP := 10.0

const SCENARIO_LABELS := ["A", "B", "C", "D", "E"]
const SCENARIO_TIPS := [
	"Horizontal: player (2,5) to ball (8,5)",
	"Vertical: player (5,8) to ball (5,2)",
	"L shape: player (3,5) to ball (10,1)",
	"Reverse L: player (8,2) to ball (2,8)",
	"Multi-segment: player (3,5) to ball (5,5)",
]


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0:
			_feedback.visible = false


func bind(callbacks: Dictionary) -> void:
	_reset_btn.pressed.connect(callbacks["reset"])
	for i in _scenario_btns.size():
		_scenario_btns[i].pressed.connect(callbacks["scenario"].bind(i))
	_debug_btn.toggled.connect(callbacks["debug"])
	_grid_btn.toggled.connect(callbacks["grid"])


func set_status(text: String) -> void:
	if _status:
		_status.text = "Movement: " + text


## Status pill without the "Movement:" prefix, for phases the route system does
## not own (the coach's feed, a loose ball, the catch itself).
func set_phase_status(text: String) -> void:
	if _status:
		_status.text = text


func set_instruction(text: String) -> void:
	if _instruction:
		_instruction.text = text


func show_message(text: String, good: bool) -> void:
	_feedback_label.text = text
	var sb := _feedback.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.bg_color = Color(0.1, 0.62, 0.36, 0.94) if good else Color(0.78, 0.52, 0.16, 0.94)
	_feedback.visible = true
	_feedback_timer = 1.8


func set_debug(info: Dictionary) -> void:
	if _debug_label == null:
		return
	var txt := ""
	txt += "Player: %s\n" % info["player"]
	txt += "Target: %s\n" % info["target"]
	txt += "Route: %s\n" % info["route"]
	txt += "Grid Distance: %s\n" % str(info["distance"])
	txt += "Est. Move Time: %.2fs\n" % float(info["time"])
	txt += "Gesture State: %s\n" % info["state"]
	txt += "Route Segments: %d\n" % int(info["segments"])
	var extra_txt := "-"
	if int(info.get("extra", -1)) >= 0:
		extra_txt = "+%d over optimal" % int(info["extra"])
	txt += "Optimality Gap: %s\n" % extra_txt
	txt += "Coach: %s\n" % info.get("coach", "-")
	txt += "Shot: %s" % info.get("shot", "-")
	_debug_label.text = txt


func set_debug_panel_visible(visible: bool) -> void:
	if _debug_panel:
		_debug_panel.visible = visible


## --- Player avatar ----------------------------------------------------------
## The avatar is the only place the player's face reacts to play. Main reports
## what just happened in game terms and the avatar picks the expression; the
## art itself lives in res://images/players/<player_name>/ (see avatar.gd).


## Shows an expression by name: "default", "happy", "sad", "angry", "excited".
## An expression with no art supplied yet falls back to the default image.
func set_avatar_expression(expression: String) -> void:
	if _avatar:
		_avatar.set_expression(expression)


## A catch was taken cleanly, which is the game's perfect catch: happy.
func avatar_catch_made() -> void:
	if _avatar:
		_avatar.react_catch_made()


## A catch was dropped: sad, or angry when it is the second one in a row.
func avatar_catch_missed() -> void:
	if _avatar:
		_avatar.react_catch_missed()


## A shot went in: excited.
func avatar_shot_made() -> void:
	if _avatar:
		_avatar.react_shot_made()


## A shot was missed: angry.
func avatar_shot_missed() -> void:
	if _avatar:
		_avatar.react_shot_missed()


## --- Shot power meter --------------------------------------------------------
## Shown only while the token is holding the ball. Main owns both that state and
## the distance the meter sizes its required range from; the meter itself - the
## track, the sweeping needle and the required band - lives in power_gauge.gd.
## It never takes input, so it cannot swallow a drag aimed at the court.


func set_power_gauge_visible(on: bool) -> void:
	if _power_gauge:
		_power_gauge.set_active(on)


func set_power_gauge_distance(cells: float) -> void:
	if _power_gauge:
		_power_gauge.set_distance_cells(cells)


## The range of needle positions that would be an accurate shot at the distance
## the meter is currently reading, as a (low, high) pair in 0..1. Vector2.ZERO
## before the meter has been built.
func power_gauge_required_range() -> Vector2:
	if _power_gauge:
		return _power_gauge.required_range()
	return Vector2.ZERO


## Drives the needle from outside, for a shooting move that charges its own
## power instead of the meter's preview sweep.
func set_power_gauge_power(value: float) -> void:
	if _power_gauge:
		_power_gauge.set_power(value)


## Flashes a big kinetic rating word (PERFECT / GOOD / OK) in the center of
## the screen for about two seconds. Any previous rating is replaced.
func flash_rating(word: String, color: Color) -> void:
	if _rating_tween and _rating_tween.is_valid():
		_rating_tween.kill()
		_rating_tween = null
	if _rating_label:
		_rating_label.queue_free()
		_rating_label = null
	var label := Label.new()
	label.text = word
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 88)
	label.add_theme_color_override("font_color", color)
	# Heavy outline plus a drop shadow makes the default font read as bold.
	label.add_theme_constant_override("outline_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	add_child(label)
	_rating_label = label
	# Start slightly below center, pop in with a back-ease overshoot, then float
	# up to center while holding, before fading out at roughly the two second mark.
	label.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	label.offset_top = 34.0
	label.offset_bottom = 34.0
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.1)
	tw.tween_property(label, "scale", Vector2(1.15, 1.15), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "offset_top", 0.0, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "offset_bottom", 0.0, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.05)
	tw.tween_property(label, "modulate:a", 0.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(label.queue_free)
	_rating_tween = tw


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Critical: this invisible full-screen container must not swallow touches.
	# A default MOUSE_FILTER_STOP Control consumes every press over the court,
	# so drag events never reach the game's _unhandled_input on mobile.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Player avatar, top-left corner: a rounded black-bordered box that reacts to
	# the last catch or shot. It sits on the same ignore-only root as the rest of
	# the HUD, so it never swallows a drag aimed at the court.
	_avatar = PlayerAvatar.new()
	_avatar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_avatar.offset_left = AVATAR_MARGIN
	_avatar.offset_top = AVATAR_TOP
	_avatar.offset_right = AVATAR_MARGIN + PlayerAvatar.BOX_SIZE
	_avatar.offset_bottom = AVATAR_TOP + PlayerAvatar.BOX_SIZE
	root.add_child(_avatar)

	# Top bar: scenarios left, status and toggles right. Its left edge clears the
	# avatar so the scenario buttons never sit over the player's face.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = AVATAR_MARGIN * 2.0 + PlayerAvatar.BOX_SIZE
	bar.offset_right = -10.0
	bar.offset_top = 8.0
	bar.offset_bottom = 46.0
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(left)

	for i in SCENARIO_LABELS.size():
		var b := _make_button(SCENARIO_LABELS[i])
		b.tooltip_text = SCENARIO_TIPS[i]
		b.custom_minimum_size = Vector2(38, 34)
		left.add_child(b)
		_scenario_btns.append(b)

	_reset_btn = _make_button("RESET")
	_reset_btn.custom_minimum_size = Vector2(88, 34)
	_reset_btn.tooltip_text = "New random player and ball positions"
	left.add_child(_reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(right)

	_status = Label.new()
	_status.text = "Movement: READY"
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	var status_pill := PanelContainer.new()
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = Color(0.05, 0.22, 0.34, 0.82)
	pill_sb.set_corner_radius_all(12)
	pill_sb.set_content_margin_all(7)
	status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_pill.add_theme_stylebox_override("panel", pill_sb)
	status_pill.add_child(_status)
	right.add_child(status_pill)

	_debug_btn = _make_toggle("Debug", true)
	right.add_child(_debug_btn)
	_grid_btn = _make_toggle("Grid", false)
	right.add_child(_grid_btn)

	# Instruction line, bottom center.
	var instruction_panel := PanelContainer.new()
	instruction_panel.anchor_left = 0.15
	instruction_panel.anchor_right = 0.85
	instruction_panel.anchor_top = 1.0
	instruction_panel.anchor_bottom = 1.0
	instruction_panel.offset_top = -52.0
	instruction_panel.offset_bottom = -10.0
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var instr_sb := StyleBoxFlat.new()
	instr_sb.bg_color = Color(0.05, 0.22, 0.34, 0.62)
	instr_sb.set_corner_radius_all(12)
	instr_sb.set_content_margin_all(8)
	instruction_panel.add_theme_stylebox_override("panel", instr_sb)
	root.add_child(instruction_panel)
	_instruction = Label.new()
	_instruction.text = "Drag a path from the player to the ball."
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction.add_theme_font_size_override("font_size", 15)
	_instruction.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	instruction_panel.add_child(_instruction)

	# Transient feedback near the top center.
	var feedback_row := HBoxContainer.new()
	feedback_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	feedback_row.offset_left = 0.0
	feedback_row.offset_right = 0.0
	feedback_row.offset_top = 56.0
	feedback_row.offset_bottom = 102.0
	feedback_row.alignment = BoxContainer.ALIGNMENT_CENTER
	feedback_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feedback_row)
	_feedback = PanelContainer.new()
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback.visible = false
	var fb_sb := StyleBoxFlat.new()
	fb_sb.bg_color = Color(0.1, 0.62, 0.36, 0.94)
	fb_sb.set_corner_radius_all(14)
	fb_sb.set_content_margin_all(9)
	_feedback.add_theme_stylebox_override("panel", fb_sb)
	feedback_row.add_child(_feedback)
	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 17)
	_feedback_label.add_theme_color_override("font_color", Color(1, 1, 1, 1.0))
	_feedback.add_child(_feedback_label)

	# Developer debug panel (right center, toggleable, never blocks touches).
	_debug_panel = PanelContainer.new()
	_debug_panel.anchor_left = 1.0
	_debug_panel.anchor_right = 1.0
	_debug_panel.anchor_top = 0.5
	_debug_panel.anchor_bottom = 0.5
	_debug_panel.offset_left = -268.0
	_debug_panel.offset_right = -12.0
	_debug_panel.offset_top = -150.0
	_debug_panel.offset_bottom = 150.0
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dbg_sb := StyleBoxFlat.new()
	dbg_sb.bg_color = Color(0.03, 0.12, 0.18, 0.82)
	dbg_sb.set_corner_radius_all(12)
	dbg_sb.set_content_margin_all(10)
	_debug_panel.add_theme_stylebox_override("panel", dbg_sb)
	root.add_child(_debug_panel)
	_debug_label = Label.new()
	_debug_label.custom_minimum_size = Vector2(236, 0)
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.95, 1.0))
	_debug_panel.add_child(_debug_label)

	# Shot power meter, floating in the middle of the screen. It is the last child
	# on this ignore-only root, so it sits over the rest of the HUD without ever
	# taking a touch: a drag across the middle of the court still reaches the
	# game. It starts hidden because Main shows it only while the token holds the
	# ball (see set_power_gauge_visible).
	_power_gauge = PowerGauge.new()
	_power_gauge.name = "PowerGauge"
	# Anchored to the exact centre and pulled back by half its own size, so it
	# stays centred on the whole screen at any viewport size.
	var gauge_size := PowerGauge.GAUGE_SIZE
	_power_gauge.anchor_left = 0.5
	_power_gauge.anchor_top = 0.5
	_power_gauge.anchor_right = 0.5
	_power_gauge.anchor_bottom = 0.5
	_power_gauge.offset_left = -gauge_size.x * 0.5
	_power_gauge.offset_top = -gauge_size.y * 0.5
	_power_gauge.offset_right = gauge_size.x * 0.5
	_power_gauge.offset_bottom = gauge_size.y * 0.5
	root.add_child(_power_gauge)
	_power_gauge.set_active(false)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	_style_solid(b, Color(0.10, 0.38, 0.56, 0.92), Color(0.16, 0.48, 0.66, 0.95), Color(0.05, 0.28, 0.42, 1.0))
	return b


func _make_toggle(text: String, default_on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = default_on
	_style_solid(b, Color(0.10, 0.38, 0.56, 0.92), Color(0.16, 0.48, 0.66, 0.95), Color(0.06, 0.68, 0.55, 1.0))
	return b


func _style_solid(b: Button, normal: Color, hover: Color, pressed: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = normal
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(7)
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate() as StyleBoxFlat
	h.bg_color = hover
	b.add_theme_stylebox_override("hover", h)
	var p := sb.duplicate() as StyleBoxFlat
	p.bg_color = pressed
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	b.add_theme_font_size_override("font_size", 14)
