class_name FightCamera
extends Camera3D
## Smash-style camera: frames every fighter, zooms out as they spread apart and
## never shows past the stage's camera bounds.

## Space kept around the fighters, in meters (x: sides, y: above and below).
@export var margin := Vector2(4.5, 3.0)
@export var min_distance := 19.0
@export var max_distance := 38.0
## Downward tilt in degrees.
@export var pitch_degrees := 5.0
## How quickly the camera catches up (higher is snappier).
@export var smoothing := 5.0

var _stage: Stage
var _targets: Array[Fighter] = []
var _center := Vector2(0.0, 2.0)
var _distance := 18.0


func _ready() -> void:
	# Moved in _process from interpolated positions, so it must not be interpolated again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func setup(stage: Stage, targets: Array[Fighter]) -> void:
	_stage = stage
	_targets = targets
	var goal := _goal()
	_center = Vector2(goal.x, goal.y)
	_distance = goal.z
	_apply()


func _process(delta: float) -> void:
	if not _stage:
		return
	var goal := _goal()
	var t := 1.0 - exp(-smoothing * delta)
	_center = _center.lerp(Vector2(goal.x, goal.y), t)
	_distance = lerpf(_distance, goal.z, t)
	_apply()


## Target framing as (center x, center y, distance).
func _goal() -> Vector3:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for fighter in _targets:
		if not is_instance_valid(fighter) or not fighter.visible:
			continue
		var p := fighter.get_global_transform_interpolated().origin
		low = low.min(Vector2(p.x, p.y))
		high = high.max(Vector2(p.x, p.y + Units.to_meters(fighter.stats.height)))
	if low.x == INF:
		low = Vector2(-2.0, 0.0)
		high = Vector2(2.0, 2.0)
	low -= margin
	high += margin

	var bounds := _stage.camera_bounds
	var half_tan := tan(deg_to_rad(fov) / 2.0)
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var size := (high - low).min(bounds.size)
	var distance := maxf(size.y / 2.0 / half_tan, size.x / 2.0 / (half_tan * aspect))
	distance = clampf(distance, min_distance, max_distance)

	# Keep the visible area inside the camera bounds.
	var half_view := Vector2(distance * half_tan * aspect, distance * half_tan)
	var center := (low + high) / 2.0
	center.x = _clamp_axis(center.x, bounds.position.x, bounds.end.x, half_view.x)
	center.y = _clamp_axis(center.y, bounds.position.y, bounds.end.y, half_view.y)
	return Vector3(center.x, center.y, distance)


func _apply() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	position = Vector3(_center.x, _center.y + sin(pitch) * _distance, cos(pitch) * _distance)
	rotation = Vector3(-pitch, 0.0, 0.0)


static func _clamp_axis(value: float, low: float, high: float, half_view: float) -> float:
	if high - low <= half_view * 2.0:
		return (low + high) / 2.0
	return clampf(value, low + half_view, high - half_view)
