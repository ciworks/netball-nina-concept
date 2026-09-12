class_name GestureInterpreter
extends RefCounted
## Converts a freehand finger stroke into a clean orthogonal grid route.
##
## Direction locking: once horizontal or vertical motion dominates it is locked
## in. A new segment only begins after the current axis is exhausted and the
## finger has clearly moved at least `corner_cells` on the other axis. This
## tolerates wobble while still supporting multi-segment L/Z routes.


enum Axis { NONE, H, V }

const GRID_MIN := 0
const GRID_MAX := 10
const MAX_PUSH_ITERATIONS := 96

## Cells of perpendicular travel required to start a new corner segment.
var corner_cells := 1

var _axis: int = Axis.NONE
var _last_segment_axis: int = Axis.NONE
var _points: Array[Vector2i] = []
var _pen := Vector2i.ZERO


func begin(start_cell: Vector2i) -> void:
	_points.clear()
	_axis = Axis.NONE
	_last_segment_axis = Axis.NONE
	_pen = start_cell
	_points.append(start_cell)


func push(raw_grid: Vector2) -> void:
	if _points.is_empty():
		return
	var desired := _clamp_cell(Vector2i(roundi(raw_grid.x), roundi(raw_grid.y)))
	var guard := 0
	while desired != _pen and guard < MAX_PUSH_ITERATIONS:
		guard += 1
		var d := desired - _pen
		if _axis == Axis.NONE:
			_axis = Axis.H if absi(d.x) >= absi(d.y) else Axis.V
		if _axis == Axis.H:
			if d.x == 0:
				if absi(d.y) >= corner_cells:
					_axis = Axis.V
					continue
				break
			_pen.x += signi(d.x)
		else:
			if d.y == 0:
				if absi(d.x) >= corner_cells:
					_axis = Axis.H
					continue
				break
			_pen.y += signi(d.y)
		_record_pen(_axis)


func finish() -> Array[Vector2i]:
	var result := get_route()
	reset()
	return result


func get_route() -> Array[Vector2i]:
	return _points.duplicate()


func reset() -> void:
	_points.clear()
	_axis = Axis.NONE
	_last_segment_axis = Axis.NONE


func _record_pen(axis_moved: int) -> void:
	if _points.size() >= 2 and _last_segment_axis == axis_moved:
		_points[_points.size() - 1] = _pen
	else:
		_points.append(_pen)
		_last_segment_axis = axis_moved


func _clamp_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, GRID_MIN, GRID_MAX), clampi(cell.y, GRID_MIN, GRID_MAX))