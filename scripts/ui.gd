extends CanvasLayer
## Builds the prototype UI: status pill, debug and grid toggles, the contextual
## instruction line, transient feedback, and the developer debug panel. The play
## area stays clear: UI hugs the edges.
##
## The scenario quick picks (A-E) and the reset button are deliberately NOT built
## any more - the prototype drives its own rounds now. Their constants and wiring
## are kept in this file, and the functions behind them (Main.random_test() and
## Main.load_scenario()) are untouched, so the controls can be switched back on
## without re-deriving anything. See SCENARIO_LABELS and bind().


const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "ui"
const HIDE_DEBUG_KEY := "hide_debug_panel"

var _status: Label
var _instruction: Label
var _feedback: PanelContainer
var _feedback_label: Label
var _debug_panel: PanelContainer
var _debug_label: Label
var _debug_btn: Button
var _grid_btn: Button
## The reset button and the scenario quick picks are no longer built by _build(),
## so these stay null and empty. SCENARIO_LABELS / SCENARIO_TIPS and the wiring in
## bind() are kept so the controls can be rebuilt without touching main.gd.
var _reset_btn: Button
var _scenario_btns: Array[Button] = []
var _avatar: PlayerAvatar
var _shot_meter: ShotMeter

var _feedback_timer := 0.0
var _rating_label: Label
var _rating_tween: Tween

## Player avatar box, pinned to the top-left corner. The control bar starts clear
## of it so nothing overlaps as the viewport resizes.
const AVATAR_MARGIN := 12.0
const AVATAR_TOP := 10.0

## How far the rating word rests below the shot power meter's panel. The meter
## owns the middle of the screen while the token holds the ball, and a clean catch
## flashes a rating at exactly that moment, so the word reads as a caption under
## the meter instead of over it. The word's own height is measured in
## flash_rating and added to this gap.
const RATING_GAP_BELOW_GAUGE := 10.0

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
	# The reset button and the scenario quick picks are not built any more, so
	# these two are no-ops today. The wiring stays because it is the seam: rebuild
	# the buttons in _build() and they work again with main.gd unchanged - it
	# still passes "reset" (random_test) and "scenario" (load_scenario) here.
	if _reset_btn != null:
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
	if _debug_btn and _debug_btn.button_pressed != visible:
		_debug_btn.set_pressed_no_signal(visible)
	_save_debug_setting(visible)


func _load_debug_setting() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var hide_debug := bool(cfg.get_value(SETTINGS_SECTION, HIDE_DEBUG_KEY, false))
	if _debug_btn:
		_debug_btn.set_pressed_no_signal(not hide_debug)
	if _debug_panel:
		_debug_panel.visible = not hide_debug


func _save_debug_setting(visible: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, HIDE_DEBUG_KEY, not visible)
	cfg.save(SETTINGS_PATH)


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


## --- Shot meter -------------------------------------------------------------
## The power bar and the direction dial are one control: the meter. It is shown
## only while the token is holding the ball, it is MOUSE_FILTER_IGNORE, and it
## never reads input itself - Main owns the possession state, the distance that
## sizes the required power range, the optimal direction, and the hold-and-release
## that selects a power value and then aims the dial. The control itself (the bar,
## the charging needle, the required band and the dial) lives in shot_meter.gd,
## and Main reads the press and release and drives it through the calls below, so
## nothing here can swallow a drag aimed at the court.


func set_shot_meter_visible(on: bool) -> void:
	if _shot_meter:
		_shot_meter.set_active(on)


func set_shot_meter_distance(cells: float) -> void:
	if _shot_meter:
		_shot_meter.set_distance_cells(cells)


func set_shot_meter_optimal(t: float) -> void:
	if _shot_meter:
		_shot_meter.set_optimal(t)


## The range of bar positions that would be an accurate shot at the distance the
## meter is currently reading, as a (low, high) pair in 0..1. Vector2.ZERO before
## the meter has been built.
func shot_meter_required_range() -> Vector2:
	if _shot_meter:
		return _shot_meter.required_range()
	return Vector2.ZERO


## The range of directions that would be an accurate shot, as a (low, high) pair
## in 0..1 across the dial. Vector2.ZERO before the meter has been built.
func shot_meter_valid_range() -> Vector2:
	if _shot_meter:
		return _shot_meter.valid_range()
	return Vector2.ZERO


## True while the aim needle sits inside the dial's green range.
func shot_meter_in_valid_range() -> bool:
	if _shot_meter:
		return _shot_meter.in_valid_range()
	return false


## Drives the power needle from outside, for a shooting move that charges its own
## power instead of the player's hold.
func set_shot_meter_power(value: float) -> void:
	if _shot_meter:
		_shot_meter.set_power(value)


## The player pressed down while holding the ball, so the power needle starts
## charging from zero.
func shot_meter_begin_charge() -> void:
	if _shot_meter:
		_shot_meter.begin_charge()


## The player let go, so the value the needle reached is the selected power and
## the direction dial becomes aimable.
func shot_meter_release_charge() -> void:
	if _shot_meter:
		_shot_meter.release_charge()


## The power value the player has selected, 0..1. 0.0 before the meter exists.
func shot_meter_power() -> float:
	if _shot_meter:
		return _shot_meter.power()
	return 0.0


## A press at screen_pos, in viewport coordinates, once a power value is locked:
## it starts the aim sweep, unless the press landed on the power bar - in which
## case Main re-picks the power instead. True means the dial now owns the press
## until it is released, and that release is the shot. The press position is only
## used for that test: the needle sweeps the dial by itself.
func shot_meter_begin_aim(screen_pos: Vector2) -> bool:
	if _shot_meter:
		return _shot_meter.begin_aim(screen_pos)
	return false


## The player let go, so the direction the needle reached is the selected one.
func shot_meter_lock_direction() -> void:
	if _shot_meter:
		_shot_meter.lock_direction()


## The direction the player has selected, as a 0..1 dial position.
func shot_meter_direction() -> float:
	if _shot_meter:
		return _shot_meter.direction()
	return 0.0


## True once a power value has been locked, i.e. the dial is lit and aimable.
func shot_meter_direction_active() -> bool:
	if _shot_meter:
		return _shot_meter.direction_active()
	return false


## Flashes a big kinetic rating word (PERFECT / GOOD / OK) below the shot meter,
## in the middle of the screen's lower half. Any previous rating is replaced.
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
	# The word rests below the shot power meter rather than over the middle of the
	# screen: the meter is up whenever the token holds the ball, and a clean catch
	# - which is exactly when this flashes - is what starts that possession. The
	# offset is measured from the screen centre, so the word keeps clearing the
	# meter however the viewport is stretched.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var word_half: float = label.get_theme_font("font").get_string_size(
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).y * 0.5
	var rating_y: float = ShotMeter.METER_SIZE.y * 0.5 + RATING_GAP_BELOW_GAUGE + word_half
	# Start slightly lower still, pop in with a back-ease overshoot, then float up
	# into place while holding, before fading out at roughly the two second mark.
	label.pivot_offset = Vector2(vp_size.x * 0.5, vp_size.y * 0.5 + rating_y)
	label.offset_top = rating_y + 34.0
	label.offset_bottom = rating_y + 34.0
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.1)
	tw.tween_property(label, "scale", Vector2(1.15, 1.15), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "offset_top", rating_y, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "offset_bottom", rating_y, 1.1) \
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

	# Top bar: status and toggles, pushed to the right by a spacer. Its left edge
	# still clears the avatar. The scenario quick picks (A-E) and the reset button
	# that used to sit on the left are not built any more, so nothing occupies
	# that space today; SCENARIO_LABELS / SCENARIO_TIPS and the wiring in bind()
	# are still here if they are wanted back.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = AVATAR_MARGIN * 2.0 + PlayerAvatar.BOX_SIZE
	bar.offset_right = -10.0
	bar.offset_top = 8.0
	bar.offset_bottom = 46.0
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

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
	_load_debug_setting()

	# The shot meter - the power bar and the direction dial in one control -
	# floating in the middle of the screen. It is the last child on this
	# ignore-only root, so it sits over the rest of the HUD without ever taking a
	# touch: a drag across the middle of the court still reaches the game. It
	# starts hidden because Main shows it only while the token holds the ball
	# (see set_shot_meter_visible).
	_shot_meter = ShotMeter.new()
	_shot_meter.name = "ShotMeter"
	# Anchored to the exact centre and pulled back by half its own size, so it
	# stays centred on the whole screen at any viewport size.
	var meter_size := ShotMeter.METER_SIZE
	_shot_meter.anchor_left = 0.5
	_shot_meter.anchor_top = 0.5
	_shot_meter.anchor_right = 0.5
	_shot_meter.anchor_bottom = 0.5
	_shot_meter.offset_left = -meter_size.x * 0.5
	_shot_meter.offset_top = -meter_size.y * 0.5
	_shot_meter.offset_right = meter_size.x * 0.5
	_shot_meter.offset_bottom = meter_size.y * 0.5
	root.add_child(_shot_meter)
	_shot_meter.set_active(false)


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
