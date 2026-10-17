class_name Stage
extends Node3D
## Base for stage scenes: the fighting area, its blast zones and camera
## limits, spawn points, soft platforms and ledges.
##
## Stages are built on the XY plane (fighters move in X and Y, Z is depth).
## Put [SoftPlatform]s and [StageLedge]s anywhere under the stage; they are
## found automatically. Solid ground is any [StaticBody3D] on the world layer.

## Fighters past these bounds (meters) are KO'd. Right and top are the end corner.
@export var blast_zone := Rect2(-24.0, -15.0, 48.0, 37.0)
## The camera never shows anything outside these bounds (meters).
@export var camera_bounds := Rect2(-16.0, -8.0, 32.0, 21.0)
## Spawn points, in player order.
@export var spawn_points: Array[Marker3D] = []
## Where the revival platform appears after a KO.
@export var respawn_marker: Marker3D

var soft_platforms: Array[SoftPlatform] = []
var ledges: Array[StageLedge] = []


func _ready() -> void:
	for node in find_children("*", "SoftPlatform", true, false):
		soft_platforms.append(node as SoftPlatform)
	for node in find_children("*", "StageLedge", true, false):
		ledges.append(node as StageLedge)


func spawn_point(index: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	return spawn_points[index % spawn_points.size()].global_position


func respawn_point() -> Vector3:
	return respawn_marker.global_position if respawn_marker else Vector3(0.0, 6.0, 0.0)
