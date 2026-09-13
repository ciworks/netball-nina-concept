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

var _feedback_timer := 0.0
var _rating_label: Label
var _rating_tween: Tween

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
	txt += "Coach: %s" % info.get("coach", "-")
	_debug_label.text = txt


func set_debug_panel_visible(visible: bool) -> void:
	if _debug_panel:
		_debug_panel.visible = visible


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

	# Top bar: scenarios left, status and toggles right.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10.0
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
