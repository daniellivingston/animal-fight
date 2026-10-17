class_name AttackState
extends FighterState
## Performing a [MoveData]: ground attacks, smash attacks (with charge),
## aerials and specials.

## Moveset slot the move came from; also its id in the stale-move queue.
var slot: StringName
var move: MoveData
## Hitboxes placed in the world this frame (see [method place_hitboxes]).
var active_hitboxes: Array[ActiveHitbox] = []

var _charge_frames := 0
var _charging := false
var _started_in_air := false
var _victims: Dictionary[Fighter, bool] = {}
var _previous_centers: Dictionary[HitboxData, Vector2] = {}


func _init(p_fighter: Fighter, p_slot: StringName, p_move: MoveData) -> void:
	super(p_fighter)
	slot = p_slot
	move = p_move


func state_name() -> StringName:
	return StringName(move.display_name) if not move.display_name.is_empty() else slot


func enter() -> void:
	_started_in_air = not fighter.grounded


func update() -> void:
	var f := fighter
	if _update_charge():
		return
	if move.reverse_frame == frame and f.input.current.stick.x * f.facing <= -InputTracker.PRESS_THRESHOLD:
		f.facing = -f.facing
		f.velocity_self.x = -f.velocity_self.x
	if frame > move.total_frames:
		if move.ends_in_helpless and not f.grounded:
			f.change_state(AirState.new(f, false, true, move.landing_lag))
		else:
			f.to_neutral()
		return

	if move.is_in_motion(frame):
		var speed_x := move.motion_velocity.x * f.facing + f.input.current.stick.x * move.motion_steer
		if not move.gravity_during_motion or frame == move.motion_start:
			f.velocity_self = Vector2(speed_x, move.motion_velocity.y)
		else:
			f.velocity_self.x = speed_x
			f.apply_gravity()
		f.fast_falling = false
	elif f.grounded:
		f.apply_traction()
	else:
		f.try_fast_fall()
		f.apply_gravity()
		f.apply_air_drift()


## Smash charge: holding the button at [member MoveData.charge_frame] freezes
## the move for up to 60 frames. Returns true while charging.
func _update_charge() -> bool:
	if move.charge_frame <= 0:
		return false
	var held := fighter.input.current.attack or fighter.input.current.smash
	if frame == move.charge_frame and held and _charge_frames == 0:
		_charging = true
	if not _charging:
		return false
	if held and _charge_frames < SmashFormulas.SMASH_CHARGE_MAX_FRAMES:
		_charge_frames += 1
		frame -= 1
		fighter.apply_traction()
		return true
	_charging = false
	return false


## Damage multiplier from the smash charge (1.0 to 1.4).
func charge_multiplier() -> float:
	var t := float(_charge_frames) / SmashFormulas.SMASH_CHARGE_MAX_FRAMES
	return lerpf(1.0, SmashFormulas.SMASH_CHARGE_FULL, t)


func is_charging() -> bool:
	return _charging


## Places this frame's active hitboxes in the world, sweeping each from where
## it was last frame. Called by the fighter after it moves.
func place_hitboxes() -> void:
	active_hitboxes.clear()
	var centers: Dictionary[HitboxData, Vector2] = {}
	if not _charging:
		var feet := Units.point_to_units(fighter.global_position)
		for hitbox in move.active_hitboxes(frame):
			var center := feet + Vector2(hitbox.offset.x * fighter.facing, hitbox.offset.y)
			active_hitboxes.append(ActiveHitbox.new(hitbox, _previous_centers.get(hitbox, center), center))
			centers[hitbox] = center
	_previous_centers = centers


func has_hit(victim: Fighter) -> bool:
	return _victims.has(victim)


func mark_hit(victim: Fighter) -> void:
	_victims[victim] = true


func on_landed() -> void:
	if not _started_in_air and move.landing_lag <= 0:
		return
	if move.autocancels(frame):
		fighter.land()
	else:
		fighter.change_state(LandingState.new(fighter, move.landing_lag))


func on_left_ground() -> void:
	pass


func stops_at_edges() -> bool:
	return move.motion_velocity.y <= 0.0


func can_grab_ledge() -> bool:
	return move.ledge_grab_frame > 0 and frame >= move.ledge_grab_frame


func grabs_ledge_while_rising() -> bool:
	return can_grab_ledge()
