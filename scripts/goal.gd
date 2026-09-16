class_name GoalZone
extends Node2D
## Visual goal container plus an independent gameplay scoring zone.
##
## The Sprite2D is presentation only. The Area2D is the logical scoring region,
## and the exported values below tune it without changing the post art.

@export_category("Goal placement")
@export var goal_cell: Vector2i = Vector2i(10, 5)
@export_range(-2.0, 2.0, 0.01, "suffix: cells") var hoop_lateral_offset_cells: float = -0.19
@export_range(0.1, 4.0, 0.05, "suffix: cells") var hoop_height_cells: float = 1.7

@export_category("Scoring zone")
@export_range(0.1, 4.0, 0.05, "suffix: cells") var scoring_zone_width_cells: float = 1.2
@export_range(0.1, 4.0, 0.05, "suffix: cells") var scoring_zone_height_cells: float = 0.9
@export_range(0.0, 4.0, 0.05, "suffix: cells") var scoring_zone_depth_cells: float = 1.0

@export_category("Shot entry")
@export var required_trajectory_direction: Vector2 = Vector2.RIGHT
@export_range(0.0, 180.0, 1.0, "suffix: degrees") var trajectory_tolerance_degrees: float = 135.0
@export var require_descending_entry: bool = false

@onready var scoring_zone: Area2D = $ScoringZone
@onready var scoring_shape: CollisionShape2D = $ScoringZone/CollisionShape2D
@onready var hoop_target: Marker2D = $HoopTarget

var _cell_size := Vector2.ONE


## Place the goal base in screen space and resize the invisible scoring shape.
## The parent position is the visual post foot and the Area2D is lifted to the
## logical hoop height independently of the post texture pivot.
func layout(base_screen_position: Vector2, cell_size: Vector2) -> void:
	_cell_size = cell_size
	position = base_screen_position
	hoop_target.position = Vector2(
		hoop_lateral_offset_cells * cell_size.x,
		-hoop_height_cells * cell_size.y)
	# The scoring area follows the dedicated hoop marker, not the post origin.
	scoring_zone.position = hoop_target.position
	var shape := scoring_shape.shape as RectangleShape2D
	if shape != null:
		shape.size = Vector2(
			maxf(scoring_zone_width_cells * cell_size.x, 8.0),
			maxf(scoring_zone_height_cells * cell_size.y, 8.0))


func scoring_floor_logical(court_origin: Vector2, cell_size: Vector2) -> Vector2:
	return court_origin + Vector2(goal_cell.x * cell_size.x, goal_cell.y * cell_size.y)


func accepts_entry(
		screen_point: Vector2,
		arrival_floor_logical: Vector2,
		goal_floor_logical: Vector2,
		entry_direction_screen: Vector2,
		descending: bool
	) -> bool:
	if not _screen_point_inside_zone(screen_point):
		return false
	var depth_offset_cells := Vector2(
			(arrival_floor_logical.x - goal_floor_logical.x) / maxf(_cell_size.x, 0.001),
			(arrival_floor_logical.y - goal_floor_logical.y) / maxf(_cell_size.y, 0.001))
	if depth_offset_cells.length() > scoring_zone_depth_cells:
		return false
	if require_descending_entry and not descending:
		return false
	var required := required_trajectory_direction.normalized()
	var incoming := entry_direction_screen.normalized()
	if required.length_squared() > 0.001 and incoming.length_squared() > 0.001:
		var alignment := clampf(required.dot(incoming), -1.0, 1.0)
		var angle := rad_to_deg(acos(alignment))
		if angle > trajectory_tolerance_degrees:
			return false
	return true


func _screen_point_inside_zone(screen_point: Vector2) -> bool:
	var shape := scoring_shape.shape as RectangleShape2D
	if shape == null:
		return false
	var local := scoring_zone.to_local(screen_point)
	return absf(local.x) <= shape.size.x * 0.5 and absf(local.y) <= shape.size.y * 0.5
