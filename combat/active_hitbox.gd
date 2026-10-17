class_name ActiveHitbox
extends RefCounted
## A hitbox placed in the world for one frame. It sweeps from where it was last
## frame to where it is now, so fast moves can't skip through a hurtbox.

var data: HitboxData
## Center last frame, in units (same as [member to] on the first active frame).
var from: Vector2
## Center this frame, in units.
var to: Vector2


func _init(p_data: HitboxData, p_from: Vector2, p_to: Vector2) -> void:
	data = p_data
	from = p_from
	to = p_to
