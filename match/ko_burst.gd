class_name KOBurst
extends CPUParticles3D
## One-shot burst where a fighter crossed a blast zone. Frees itself when done.


static func spawn(parent: Node, at: Vector3, color: Color) -> void:
	var burst := KOBurst.new()
	burst.color = color
	parent.add_child(burst)
	burst.global_position = at


func _ready() -> void:
	one_shot = true
	explosiveness = 0.95
	amount = 48
	lifetime = 0.9
	direction = Vector3.UP
	spread = 180.0
	gravity = Vector3.ZERO
	initial_velocity_min = 6.0
	initial_velocity_max = 14.0
	scale_amount_min = 0.15
	scale_amount_max = 0.4
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	sphere.material = material
	mesh = sphere
	emitting = true
	finished.connect(queue_free)
