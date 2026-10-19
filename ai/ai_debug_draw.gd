class_name AiDebugDraw
extends MeshInstance3D
## AI debug drawing (F3), visual only: for every CPU, a ghost where it
## perceives its opponent (delayed and extrapolated) next to the real one, the
## opponent's predicted path, the planned recovery path, and the hitboxes of
## the attack it last chose, where it expects them to connect.

const _GHOST := Color(0.3, 0.9, 1.0, 0.9)
const _PATH := Color(0.3, 0.9, 1.0, 0.45)
const _RECOVERY := Color(1.0, 0.85, 0.2, 0.9)
const _HITBOX := Color(1.0, 0.3, 0.3, 0.9)
const _CIRCLE_SEGMENTS := 12

var _match: Match
var _lines := ImmediateMesh.new()
var _scratch := PackedVector2Array()


func _ready() -> void:
	mesh = _lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material_override = material
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func setup(match_node: Match) -> void:
	_match = match_node


func _process(_delta: float) -> void:
	_lines.clear_surfaces()
	visible = DebugSettings.show_ai_debug and _match != null
	if not visible:
		return
	var any := false
	for fighter in _match.fighters:
		var cpu := fighter.controller as CpuController if is_instance_valid(fighter) else null
		if not cpu or not cpu.has_target() or cpu.mode != CpuController.Mode.FIGHT:
			continue
		if not any:
			_lines.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		_draw_cpu(cpu)
	if any:
		_lines.surface_end()


func _draw_cpu(cpu: CpuController) -> void:
	var target := cpu.target
	# Ghost: the perceived hurt capsule, as a box.
	var feet := target.position
	var r := target.hurt_radius
	_box(Rect2(feet.x - r, feet.y, r * 2.0, target.hurt_height), _GHOST)
	# Its predicted path.
	if cpu.stage:
		Predict.trajectory(target, 30, cpu.stage, _scratch)
		_polyline(_scratch, _PATH)
	var recover := cpu.situation as RecoverSituation
	if recover:
		_polyline(recover.debug_path(), _RECOVERY)
	var option := cpu.last_option
	if option and cpu.frame - cpu.last_option_frame <= option.frames:
		var profile := option.profile
		var move_frame := clampi(option.frames - option.delay, profile.startup, profile.active_end)
		var shift := profile.displacement[mini(move_frame, profile.total)]
		var origin := cpu.last_option_origin + Vector2(shift.x * option.facing, shift.y)
		for hitbox in MoveBook.world_hitboxes(profile, move_frame, origin, option.facing):
			_circle(Vector2(hitbox.x, hitbox.y), hitbox.z, _HITBOX)


func _segment(a: Vector2, b: Vector2, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(Vector3(a.x, a.y, 0.0) / Units.PER_METER + Vector3(0.0, 0.0, 0.6))
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(Vector3(b.x, b.y, 0.0) / Units.PER_METER + Vector3(0.0, 0.0, 0.6))


func _polyline(points: PackedVector2Array, color: Color) -> void:
	for i in range(1, points.size()):
		_segment(points[i - 1], points[i], color)


func _box(rect: Rect2, color: Color) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x, rect.position.y)
	var c := rect.end
	var d := Vector2(rect.position.x, rect.end.y)
	_segment(a, b, color)
	_segment(b, c, color)
	_segment(c, d, color)
	_segment(d, a, color)


func _circle(center: Vector2, radius: float, color: Color) -> void:
	for i in _CIRCLE_SEGMENTS:
		var from := center + Vector2.from_angle(TAU * i / _CIRCLE_SEGMENTS) * radius
		var to := center + Vector2.from_angle(TAU * (i + 1) / _CIRCLE_SEGMENTS) * radius
		_segment(from, to, color)
