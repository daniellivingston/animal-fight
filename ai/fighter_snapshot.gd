class_name FighterSnapshot
extends RefCounted
## What a human can see of a fighter on one frame: where it is, how it moves,
## what it's doing and how long until it can act. CPUs see other fighters only
## through snapshots, and only after their reaction delay (see [AiWorld]).
##
## It never holds input: no [InputFrame], [InputTracker] or controller. Positions
## are the feet in units, velocities units/frame, y up.

## What the fighter is doing, as read from its state (its "animation").
enum Activity {
	IDLE, WALK, DASH, RUN, CROUCH, JUMPSQUAT, AIR, HELPLESS, TUMBLE, ATTACK,
	SHIELD, DODGE, AIR_DODGE, LANDING, HITSTUN, KNOCKDOWN, LEDGE, LEDGE_ACTION,
	SHIELD_BREAK, RESPAWN, KO,
}

## [member AiWorld.frame] this was captured on (-1 = never).
var frame := -1
## Index of the fighter in [member AiWorld.fighters].
var index := 0
var position := Vector2.ZERO
var velocity_self := Vector2.ZERO
var velocity_knockback := Vector2.ZERO
var facing := 1
var grounded := false
var fast_falling := false
var activity := Activity.IDLE
var state_name := &""
var state_frame := 0
## [method FighterState.frames_until_actionable].
var actionable_in := 0
## Frames until intangibility ends (state, ledge and respawn intangibility).
var intangible_left := 0
var hitlag := 0
var percent := 0.0
var shield_hp := SmashFormulas.SHIELD_MAX
var jumps_left := 0
var air_dodge_used := false
## Current move, while attacking.
var move: MoveData
var move_slot := &""
var charging := false
## World frame the current state began on. Identifies one move or action.
var state_started := 0
## Side of the held ledge (-1 left, 1 right), 0 when not on a ledge.
var ledge_side := 0
## Index of whoever hit this fighter last (-1 = nobody since respawning).
var last_attacker := -1
## Hurt capsule height and radius in units (smaller while crouching or lying down).
var hurt_height := 0.0
var hurt_radius := 0.0
## Character knowledge: what anyone who knows the character can tell.
var stats: FighterStats
var moveset: Moveset


## Fills this snapshot from [param fighter] as it is now.
func capture(fighter: Fighter, p_index: int, p_frame: int, fighters: Array[Fighter]) -> void:
	var state := fighter.state
	frame = p_frame
	index = p_index
	position = Units.point_to_units(fighter.global_position)
	velocity_self = fighter.velocity_self
	velocity_knockback = fighter.velocity_knockback
	facing = fighter.facing
	grounded = fighter.grounded
	fast_falling = fighter.fast_falling
	activity = activity_of(fighter)
	state_name = state.state_name()
	state_frame = state.frame
	actionable_in = state.frames_until_actionable()
	intangible_left = maxi(state.intangible_frames_left(), fighter.intangible_frames)
	hitlag = fighter.hitlag_frames
	percent = fighter.percent
	shield_hp = fighter.shield_hp
	jumps_left = maxi(fighter.stats.jump_count - fighter.jumps_used, 0)
	air_dodge_used = fighter.air_dodge_used
	var attack := fighter.current_attack()
	move = attack.move if attack else null
	move_slot = attack.slot if attack else &""
	charging = attack != null and attack.is_charging()
	state_started = p_frame - state.frame + 1
	ledge_side = fighter.ledge.side if fighter.ledge else 0
	last_attacker = fighters.find(fighter.last_attacker) if fighter.last_attacker else -1
	# The hurt capsule's height, as Fighter.get_hurt_segment() shapes it.
	var fighter_stats := fighter.stats
	var height := fighter_stats.height
	if activity == Activity.CROUCH:
		height *= fighter_stats.crouch_height_ratio
	elif activity == Activity.KNOCKDOWN:
		height *= 0.4
	hurt_radius = fighter.get_hurt_radius()
	hurt_height = maxf(height, hurt_radius * 2.0)
	stats = fighter_stats
	moveset = fighter.moveset


func copy_from(other: FighterSnapshot) -> void:
	frame = other.frame
	index = other.index
	position = other.position
	velocity_self = other.velocity_self
	velocity_knockback = other.velocity_knockback
	facing = other.facing
	grounded = other.grounded
	fast_falling = other.fast_falling
	activity = other.activity
	state_name = other.state_name
	state_frame = other.state_frame
	actionable_in = other.actionable_in
	intangible_left = other.intangible_left
	hitlag = other.hitlag
	percent = other.percent
	shield_hp = other.shield_hp
	jumps_left = other.jumps_left
	air_dodge_used = other.air_dodge_used
	move = other.move
	move_slot = other.move_slot
	charging = other.charging
	state_started = other.state_started
	ledge_side = other.ledge_side
	last_attacker = other.last_attacker
	hurt_height = other.hurt_height
	hurt_radius = other.hurt_radius
	stats = other.stats
	moveset = other.moveset


func velocity() -> Vector2:
	return velocity_self + velocity_knockback


func is_valid() -> bool:
	return frame >= 0


func is_alive() -> bool:
	return activity != Activity.KO and activity != Activity.RESPAWN


func is_shielding() -> bool:
	return activity == Activity.SHIELD and state_name != &"ShieldDrop"


## Committed to something it can't cancel: endlag, lag, getups, stun.
func is_committed() -> bool:
	return actionable_in > 0


static func activity_of(fighter: Fighter) -> Activity:
	var state := fighter.state
	if state is IdleState:
		return Activity.IDLE
	if state is WalkState:
		return Activity.WALK
	if state is DashState:
		return Activity.DASH
	if state is RunState or state is RunBrakeState:
		return Activity.RUN
	if state is CrouchState:
		return Activity.CROUCH
	if state is JumpSquatState:
		return Activity.JUMPSQUAT
	if state is AirState:
		var air := state as AirState
		if air.helpless:
			return Activity.HELPLESS
		return Activity.TUMBLE if air.tumbling else Activity.AIR
	if state is AttackState:
		return Activity.ATTACK
	if state is ShieldState:
		return Activity.SHIELD
	if state is DodgeState:
		return Activity.DODGE
	if state is AirDodgeState:
		return Activity.AIR_DODGE
	if state is LandingState:
		return Activity.LANDING
	if state is HitstunState:
		return Activity.HITSTUN
	if state is KnockdownState:
		return Activity.KNOCKDOWN
	if state is LedgeHangState:
		return Activity.LEDGE
	if state is LedgeActionState:
		return Activity.LEDGE_ACTION
	if state is ShieldBreakState:
		return Activity.SHIELD_BREAK
	if state is RespawnState:
		return Activity.RESPAWN
	return Activity.KO
