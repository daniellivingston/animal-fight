class_name SoftPlatform
extends StaticBody3D
## A pass-through platform: fighters jump up through it, land on it from above
## and drop through it by flicking down. Needs a [BoxShape3D] child collision
## shape; the platform's top is the top of that box.
##
## Godot's 3D physics has no one-way collision, so each [Fighter] toggles a
## collision exception with every soft platform each frame
## (see [method Fighter._update_platform_collisions]).

var _top := 0.0


func _ready() -> void:
	collision_layer = PhysicsLayers.PLATFORM
	collision_mask = 0
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			_top = shape.global_position.y + (shape.shape as BoxShape3D).size.y * 0.5 * shape.global_basis.get_scale().y
			return
	push_warning("SoftPlatform %s has no BoxShape3D." % name)


## World height of the platform's surface, in meters.
func get_top() -> float:
	return _top
