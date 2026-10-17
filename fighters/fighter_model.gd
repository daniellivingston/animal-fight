class_name FighterModel
extends Node3D
## A fighter's visuals, kept separate from gameplay. Root of each character's
## model scene (fighters/roster/<name>/<name>_model.tscn).
##
## The placeholder models are primitive meshes under a [code]Pivot[/code] node
## (origin at the feet, nose toward +X). [method sync] poses them each frame
## from the fighter's state with squash, lean and spin, so states read clearly
## without animations. A rigged model would keep this API and drive an
## AnimationTree from [method sync] instead.

## How quickly the model turns toward its facing direction (fraction per frame).
const TURN_RATE := 0.45
## How far the model turns toward the camera, in radians, so it reads in 3D.
const CAMERA_TILT := 0.35
const HITLAG_SHAKE := 0.06
const TUMBLE_SPIN_SPEED := 0.35

var _meshes: Array[MeshInstance3D] = []
var _flash_frames := 0
var _yaw := -CAMERA_TILT
var _spin := 0.0
var _flash_material := _overlay_material(Color(1.0, 1.0, 1.0, 0.75))
var _intangible_material := _overlay_material(Color(0.55, 0.8, 1.0, 0.55))
var _charge_material := _overlay_material(Color(1.0, 0.9, 0.3, 0.5))
var _helpless_material := _overlay_material(Color(0.0, 0.0, 0.0, 0.35))

@onready var _pivot: Node3D = %Pivot


func _ready() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)


## Flashes white for a few frames (when hit).
func flash() -> void:
	_flash_frames = 4


## Poses the model for the fighter's current frame. Called once per simulation frame.
func sync(fighter: Fighter) -> void:
	var state := fighter.state
	var target_yaw := -CAMERA_TILT if fighter.facing > 0 else PI + CAMERA_TILT
	_yaw = lerp_angle(_yaw, target_yaw, TURN_RATE)

	var squash := 1.0
	var tilt := 0.0
	var offset := Vector3.ZERO
	if state is JumpSquatState or state is LandingState:
		squash = 0.8
	elif state is CrouchState:
		squash = fighter.stats.crouch_height_ratio
	elif state is DashState or state is RunState:
		tilt = -0.2
	elif state is RunBrakeState:
		tilt = 0.25
	elif state is KnockdownState:
		tilt = -PI / 2.0
	elif state is ShieldBreakState:
		tilt = sin(fighter.frame_count * 0.2) * 0.3

	if fighter.is_tumbling() and not fighter.grounded:
		_spin += TUMBLE_SPIN_SPEED
		tilt = _spin
	else:
		_spin = 0.0

	if fighter.hitlag_frames > 0 and state is HitstunState:
		offset = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * HITLAG_SHAKE

	var widen := 1.0 + (1.0 - squash) * 0.5
	_pivot.rotation = Vector3(0.0, _yaw, tilt)
	_pivot.scale = Vector3(widen, squash, widen)
	_pivot.position = offset
	_apply_overlay(fighter)


func _apply_overlay(fighter: Fighter) -> void:
	var overlay: Material = null
	var attack := fighter.current_attack()
	if _flash_frames > 0:
		_flash_frames -= 1
		overlay = _flash_material
	elif fighter.is_intangible() and not fighter.state is RespawnState:
		# Blink during long invincibility (after respawning).
		if fighter.intangible_frames < 30 or fighter.frame_count % 8 < 5:
			overlay = _intangible_material
	elif attack and attack.is_charging() and fighter.frame_count % 10 < 5:
		overlay = _charge_material
	elif fighter.state is AirState and (fighter.state as AirState).helpless:
		overlay = _helpless_material
	for mesh in _meshes:
		mesh.material_overlay = overlay


static func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	return material
