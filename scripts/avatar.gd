class_name PlayerAvatar
extends PanelContainer
## The player avatar: a rounded, black-bordered box that shows how the player
## feels about the last thing that happened on court.
##
## Art is dropped in, not generated. One PNG per expression, named
## player_expression_<expression>.png, in res://images/players/<player_name>/:
##
##   player_expression_default.png
##   player_expression_happy.png    - a perfect (clean) catch
##   player_expression_sad.png      - a dropped catch
##   player_expression_angry.png    - a missed shot, or two dropped catches in a row
##   player_expression_excited.png  - a perfect shot
##
## Nothing breaks while a file is missing: an expression with no art falls back
## to the default image, and with no art at all the box stays an empty
## black-bordered frame in its final position, ready for the files to land.


## Expression keys. Each one is also the file name suffix, so adding a new
## reaction is a matter of dropping in the matching PNG and naming it here.
const EXPRESSION_DEFAULT := "default"
const EXPRESSION_HAPPY := "happy"
const EXPRESSION_SAD := "sad"
const EXPRESSION_ANGRY := "angry"
const EXPRESSION_EXCITED := "excited"

const IMAGE_FOLDER_FORMAT := "res://images/players/%s/"
const IMAGE_FILE_FORMAT := "player_expression_%s.png"

## Folder read until a player name is set. The prototype's player.
const DEFAULT_PLAYER_NAME := "nina"

## Side of the box, in pixels.
const BOX_SIZE := 120.0
const CORNER_RADIUS := 20
const BORDER_WIDTH := 4
## Gap between the border and the image, so the rounded corners stay visible
## instead of being covered by a square photograph.
const INNER_MARGIN := 5

## Dropped catches in a row that turn the sad face into an angry one.
const ANGRY_MISS_STREAK := 2

var player_name := DEFAULT_PLAYER_NAME

var _image: TextureRect
var _expression := ""
var _miss_streak := 0


func _ready() -> void:
	custom_minimum_size = Vector2(BOX_SIZE, BOX_SIZE)
	# The box is decoration: touches must fall through to the court underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	sb.set_corner_radius_all(CORNER_RADIUS)
	sb.set_border_width_all(BORDER_WIDTH)
	sb.border_color = Color(0.0, 0.0, 0.0, 0.95)
	sb.set_content_margin_all(INNER_MARGIN)
	add_theme_stylebox_override("panel", sb)

	_image = TextureRect.new()
	# IGNORE_SIZE so the art is scaled into the box whatever it was authored at,
	# and KEEP_ASPECT_CENTERED so it is never stretched out of shape.
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)

	if _load_expression(EXPRESSION_DEFAULT) == null:
		print("[avatar] No art in %s yet - drop player_expression_<expression>.png in and the box picks it up." % (IMAGE_FOLDER_FORMAT % player_name))
	set_expression(EXPRESSION_DEFAULT)


## Points the avatar at another player's folder, e.g. "nina". Already-loaded
## expressions are re-resolved against the new folder.
func set_player_name(value: String) -> void:
	if value == "" or value == player_name:
		return
	player_name = value
	set_expression(_expression if _expression != "" else EXPRESSION_DEFAULT)


## Shows one expression by name. An expression with no art yet falls back to the
## default image, and if even that is missing the box keeps what it is showing
## rather than going blank.
func set_expression(expression: String) -> void:
	var tex := _load_expression(expression)
	if tex == null:
		tex = _load_expression(EXPRESSION_DEFAULT)
	if tex == null:
		return
	_expression = expression
	_image.texture = tex


## Name of the expression currently on screen ("" while no art has been supplied).
func current_expression() -> String:
	return _expression


## The player took the ball cleanly. This is the game's perfect catch: the coach
## only reports a caught feed when the token was set on the spot to take it (see
## CoachThrower._clean_catch). Any clean catch clears the dropped-catch streak.
func react_catch_made() -> void:
	_miss_streak = 0
	set_expression(EXPRESSION_HAPPY)


## The feed was not taken: the ball came off the token or landed away from it.
## One dropped catch reads sad, a second in a row tips over into angry.
func react_catch_missed() -> void:
	_miss_streak += 1
	set_expression(EXPRESSION_ANGRY if _miss_streak >= ANGRY_MISS_STREAK else EXPRESSION_SAD)


## A perfect shot went in.
func react_shot_made() -> void:
	set_expression(EXPRESSION_EXCITED)


## A shot missed. Straight to angry, whether or not catches were dropped before.
func react_shot_missed() -> void:
	set_expression(EXPRESSION_ANGRY)


## Dropped catches in a row right now.
func miss_streak() -> int:
	return _miss_streak


func _load_expression(expression: String) -> Texture2D:
	var path: String = (IMAGE_FOLDER_FORMAT % player_name) + (IMAGE_FILE_FORMAT % expression)
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D
