class_name AnimatedFighterModel
extends FighterModel
## A rigged model (an imported glTF instanced under [code]Pivot[/code]) whose
## AnimationPlayer is driven from the fighter's state.
##
## The player is stepped manually from [method sync], once per simulation
## frame, so animations freeze during hitlag and smash charge and an attack's
## animation is stretched to fit the move's [member MoveData.total_frames].
## The animation names default to the Quaternius animal rigs; set them per
## model scene for other rigs. Empty names fall back to [member idle].

const FRAME := 1.0 / 60.0
## Cross-fade time between animations, in seconds.
const BLEND := 0.08
## Landing and jumpsquat are a few frames long; their animation plays this fast.
const LAND_SPEED := 2.5

@export_group("Animations")
@export var idle := &"Idle"
@export var walk := &"Walk"
## Dash, run, rolls and ledge actions.
@export var run := &"Gallop"
@export var jump := &"Gallop_Jump"
@export var land := &"Jump_toIdle"
## Crouch, shield, jumpsquat and ledge hang.
@export var crouch := &"Idle_Headlow"
## Hitstun picks the next one each time the fighter is hit.
@export var hurt: Array[StringName] = [&"Idle_HitReact1", &"Idle_HitReact2"]
@export var attack := &"Attack_Headbutt"
## Back aerial, so it kicks backward. Falls back to [member attack] when empty.
@export var back_attack := &"Attack_Kick"
## Knockdown and KO.
@export var ko := &"Death"

var _player: AnimationPlayer
var _state: FighterState
var _hurt_index := 0


func _ready() -> void:
	super()
	_player = find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer
	assert(_player, "AnimatedFighterModel needs an AnimationPlayer in its model")
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for anim_name in [idle, walk, run, crouch]:
		if _player.has_animation(anim_name):
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_player.play(idle)


func _pose(fighter: Fighter) -> void:
	var state := fighter.state
	var entered := state != _state
	_state = state

	var anim := idle
	var once := false
	var speed := 1.0
	var attack_state := state as AttackState
	if attack_state:
		anim = attack
		if attack_state.slot == Moveset.BACK_AIR and not back_attack.is_empty():
			anim = back_attack
		once = true
		speed = _length(anim) / (attack_state.move.total_frames * FRAME)
		if attack_state.is_charging():
			speed = 0.0
	elif state is WalkState:
		anim = walk
		speed = clampf(absf(fighter.velocity_self.x) / fighter.stats.walk_speed, 0.4, 1.5)
	elif state is DashState or state is RunState or state is DodgeState or state is LedgeActionState:
		anim = run
	elif state is AirState or state is AirDodgeState:
		anim = jump
		once = true
	elif state is LandingState or state is RunBrakeState:
		anim = land
		once = true
		speed = LAND_SPEED
	elif state is CrouchState or state is ShieldState or state is JumpSquatState or state is LedgeHangState:
		anim = crouch
	elif state is HitstunState or state is ShieldBreakState:
		if entered and not hurt.is_empty():
			_hurt_index = (_hurt_index + 1) % hurt.size()
		anim = hurt[_hurt_index] if not hurt.is_empty() else idle
		once = true
	elif state is KnockdownState or state is KOState:
		anim = ko
		once = true
	if not _player.has_animation(anim):
		anim = idle

	var restart := once and entered
	if restart and _player.assigned_animation == anim:
		_player.stop()
	if restart or _player.assigned_animation != anim:
		_player.play(anim, BLEND)
	# Frozen during hitlag; advancing by 0 still applies a newly started animation.
	_player.advance(FRAME * speed if fighter.hitlag_frames == 0 else 0.0)

	_pivot.rotation = Vector3(0.0, _yaw, _tumble_spin(fighter))
	_pivot.position = _hitlag_shake(fighter)


## Every animation name this model uses (empty names left out).
func animation_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for anim: StringName in [idle, walk, run, jump, land, crouch, attack, back_attack, ko] + hurt:
		if not anim.is_empty():
			names.append(anim)
	return names


func _length(anim: StringName) -> float:
	return _player.get_animation(anim).length if _player.has_animation(anim) else 1.0
