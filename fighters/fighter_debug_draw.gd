class_name FighterDebugDraw
extends Node3D
## Training-mode shapes: the hurtbox capsule (yellow, blue while intangible)
## and the active hitboxes (red), shown while [member DebugSettings.show_hitboxes] is on.

var _fighter: Fighter
var _hurtbox: MeshInstance3D
var _hitboxes: Array[MeshInstance3D] = []
var _hurt_material := _material(Color(1.0, 0.85, 0.2, 0.12))
var _intangible_material := _material(Color(0.4, 0.7, 1.0, 0.3))
var _hit_material := _material(Color(1.0, 0.1, 0.1, 0.5))


func setup(fighter: Fighter) -> void:
	_fighter = fighter
	_hurtbox = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = Units.to_meters(fighter.stats.radius)
	capsule.height = 1.0
	_hurtbox.mesh = capsule
	_hurtbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hurtbox)


func sync() -> void:
	visible = DebugSettings.show_hitboxes
	if not visible:
		return
	var feet := Units.point_to_units(_fighter.global_position)

	var hurt := _fighter.get_hurt_segment()
	var radius := Units.to_meters(_fighter.get_hurt_radius())
	var bottom := Units.to_meters(hurt[0].y - feet.y) - radius
	var top := Units.to_meters(hurt[1].y - feet.y) + radius
	(_hurtbox.mesh as CapsuleMesh).height = top - bottom
	_hurtbox.position = Vector3(0.0, (top + bottom) / 2.0, 0.0)
	_hurtbox.material_override = _intangible_material if _fighter.is_intangible() else _hurt_material

	var active := _fighter.get_active_hitboxes()
	while _hitboxes.size() < active.size():
		var sphere := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		sphere.mesh = mesh
		sphere.material_override = _hit_material
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sphere)
		_hitboxes.append(sphere)
	for i in _hitboxes.size():
		var sphere := _hitboxes[i]
		sphere.visible = i < active.size()
		if sphere.visible:
			var hitbox := active[i]
			var local := (hitbox.to - feet) / Units.PER_METER
			sphere.position = Vector3(local.x, local.y, 0.0)
			sphere.scale = Vector3.ONE * Units.to_meters(hitbox.data.radius)


## Drawn on top of everything (the hurtbox would z-fight with the body mesh otherwise).
static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	return material
