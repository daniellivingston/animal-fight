class_name StageModel
extends RefCounted
## What CPUs know about a stage, built once from any [Stage]: solid ground,
## soft platforms, ledges, blast zone and respawn point, plus the queries the
## AI needs (is there ground below, how far offstage, how close to the edge).
## No per-stage scripts: all stage knowledge comes from here (fairness rule R7).
##
## Everything is in units with y up. Solid ground is read from the collision
## shapes of the stage's [StaticBody3D]s on the world layer, as boxes.

## Solid boxes: position is the bottom-left corner, end the top-right.
var solids: Array[Rect2] = []
## Soft platforms as (left, right, top).
var platforms: PackedVector3Array = PackedVector3Array()
var ledge_points: PackedVector2Array = PackedVector2Array()
## -1 for a left edge, 1 for a right edge, per ledge.
var ledge_sides: PackedInt32Array = PackedInt32Array()
## The main ground's edges and top (from the ledges).
var main_left := -80.0
var main_right := 80.0
var main_top := 0.0
## Blast zone: position is the bottom-left corner.
var blast_zone := Rect2()
var respawn_point := Vector2.ZERO
## Everything solid or soft, in one box: bodies well outside it can't touch anything.
var bounds := Rect2()
## Every surface that can be landed on, solid or soft, as (left, right, top).
var surfaces := PackedVector3Array()
var center := 0.0


func _init(stage: Stage) -> void:
	for node in stage.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body is SoftPlatform or (body.collision_layer & PhysicsLayers.WORLD) == 0:
			continue
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape and shape.shape and not shape.disabled:
				solids.append(_shape_rect(shape))
	for platform in stage.soft_platforms:
		var rect := Rect2()
		for child in platform.get_children():
			if child is CollisionShape3D:
				rect = _shape_rect(child as CollisionShape3D)
		platforms.append(Vector3(rect.position.x, rect.end.x, Units.to_units(platform.get_top())))
	for ledge in stage.ledges:
		ledge_points.append(Units.point_to_units(ledge.global_position))
		ledge_sides.append(ledge.side)
		if ledge.side < 0:
			main_left = Units.to_units(ledge.global_position.x)
		else:
			main_right = Units.to_units(ledge.global_position.x)
		main_top = Units.to_units(ledge.global_position.y)
	if stage.ledges.is_empty() and not solids.is_empty():
		var widest := solids[0]
		for rect in solids:
			if rect.size.x > widest.size.x:
				widest = rect
		main_left = widest.position.x
		main_right = widest.end.x
		main_top = widest.end.y
	var zone := stage.blast_zone
	blast_zone = Rect2(zone.position * Units.PER_METER, zone.size * Units.PER_METER)
	respawn_point = Units.point_to_units(stage.respawn_point())
	for rect in solids:
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	for platform in platforms:
		var top := Rect2(platform.x, platform.z - 1.0, platform.y - platform.x, 1.0)
		bounds = top if bounds.size == Vector2.ZERO else bounds.merge(top)
	center = (main_left + main_right) * 0.5
	for rect in solids:
		surfaces.append(Vector3(rect.position.x, rect.end.x, rect.end.y))
	surfaces.append_array(platforms)


## Top of the highest ground at or below [param point] (solid, and soft
## platforms unless [param solid_only]), or -INF over a pit.
func ground_below(point: Vector2, solid_only: bool = false) -> float:
	var best := -INF
	for rect in solids:
		if point.x >= rect.position.x and point.x <= rect.end.x and rect.end.y <= point.y + 0.5:
			best = maxf(best, rect.end.y)
	if not solid_only:
		for platform in platforms:
			if point.x >= platform.x and point.x <= platform.y and platform.z <= point.y + 0.5:
				best = maxf(best, platform.z)
	return best


func is_over_ground(x: float) -> bool:
	for rect in solids:
		if x >= rect.position.x and x <= rect.end.x:
			return true
	return false


## Horizontal distance past the main ground's edges, 0 above it.
func distance_offstage(point: Vector2) -> float:
	return maxf(maxf(main_left - point.x, point.x - main_right), 0.0)


## Distance from [param x] to the nearer edge of the main ground (negative offstage).
func edge_distance(x: float) -> float:
	return minf(x - main_left, main_right - x)


## Distance from [param x] to the main ground's edge in [param direction] (1 or -1).
func edge_distance_toward(x: float, direction: int) -> float:
	return main_right - x if direction > 0 else x - main_left


## Whether a fighter at [param point] has to recover: beside or below the main
## ground with no ground under it.
func is_offstage(point: Vector2) -> bool:
	if point.x < main_left or point.x > main_right:
		return true
	return point.y < main_top - 1.0 and ground_below(point) == -INF


## Distance to the nearest side or bottom blast zone line.
func blast_margin(point: Vector2) -> float:
	return minf(minf(point.x - blast_zone.position.x, blast_zone.end.x - point.x),
			point.y - blast_zone.position.y)


func is_outside_blast_zone(point: Vector2, in_hitstun: bool) -> bool:
	if point.x < blast_zone.position.x or point.x > blast_zone.end.x or point.y < blast_zone.position.y:
		return true
	return in_hitstun and point.y > blast_zone.end.y


## Index of the ledge nearest to [param point], or -1.
func nearest_ledge(point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in ledge_points.size():
		var distance := ledge_points[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## The ledge on the side of the stage [param point] is on.
func ledge_toward(point: Vector2) -> int:
	var center := (main_left + main_right) * 0.5
	var side := -1 if point.x < center else 1
	for i in ledge_sides.size():
		if ledge_sides[i] == side:
			return i
	return nearest_ledge(point)


func center_x() -> float:
	return center


## Which way to drift to get home from [param point] (a body [param radius]
## wide): below the ledge, toward a spot just outside the nearer edge, so the
## body clears the stage's lip and can rise to the ledge (out from under the
## stage, in from beside it); once level with the top, toward the center. The
## recovery planner simulates the same rule.
func home_direction(point: Vector2, radius: float) -> float:
	var side := -1.0 if point.x < center else 1.0
	if point.y >= main_top - 1.0:
		var edge := main_left if side < 0.0 else main_right
		# Over the edge already, or about to be: head for the middle.
		if (point.x - edge) * side < radius * 2.0 + 4.0:
			return -side
	# The middle of the band where the body clears the lip and can still reach
	# the ledge (Fighter.LEDGE_GRAB_REACH past its radius); no steering inside it.
	var reach := Fighter.LEDGE_GRAB_REACH * 0.5
	var target := (main_left if side < 0.0 else main_right) + side * (radius + reach)
	var offset := target - point.x
	if absf(offset) < reach - 0.5:
		return 0.0
	return signf(offset)


## Pushes a body (feet at [param feet], half width [param radius], height
## [param height]) out of solid ground, as the physics would. Returns which
## way it collided: 1 floor, -1 ceiling, 2 wall, 0 none. [param previous] is
## where the feet were last frame.
func collide(feet: Vector2, previous: Vector2, radius: float, height: float) -> Vector3:
	for rect in solids:
		if feet.x + radius <= rect.position.x or feet.x - radius >= rect.end.x:
			continue
		if feet.y >= rect.end.y or feet.y + height <= rect.position.y:
			continue
		if previous.y >= rect.end.y - 0.01:
			# The capsule stands on a corner only while its rounded bottom is
			# nearly over it; further out it slides off the side. (A falling,
			# drifting capsule slides off sooner than a resting one would.)
			var corner := radius * 0.3
			if feet.x >= rect.position.x - corner and feet.x <= rect.end.x + corner:
				return Vector3(feet.x, rect.end.y, 1.0)
			var outside := rect.position.x - radius if feet.x < rect.position.x else rect.end.x + radius
			return Vector3(outside, feet.y, 2.0)
		if previous.y + height <= rect.position.y + 0.01:
			return Vector3(feet.x, rect.position.y - height, -1.0)
		var x := rect.position.x - radius if previous.x < (rect.position.x + rect.end.x) * 0.5 else rect.end.x + radius
		return Vector3(x, feet.y, 2.0)
	return Vector3(feet.x, feet.y, 0.0)


func _shape_rect(shape: CollisionShape3D) -> Rect2:
	var aabb := shape.shape.get_debug_mesh().get_aabb()
	var xform := shape.global_transform
	var rect := Rect2()
	for i in 8:
		var corner := Units.point_to_units(xform * aabb.get_endpoint(i))
		rect = Rect2(corner, Vector2.ZERO) if i == 0 else rect.expand(corner)
	return rect
