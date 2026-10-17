class_name Fighter
extends CharacterBody3D
## A platform fighter: Smash-style movement, combat and stats.
##
## [Match] drives every fighter one Smash frame per physics tick: it calls
## [method tick] on each fighter, then resolves hits with [HitResolver], then
## calls [method sync_visuals]. This keeps the simulation frame-exact and
## deterministic. Positions are Godot meters on the XY plane; velocities and all
## stats use Smash units (see [Units]).
##
## Behaviour lives in [FighterState]s (fighters/states/). This class owns the
## physical state (velocities, damage, jumps, shield, hitlag) and the shared
## helpers states use: the [code]try_*[/code] actions and the movement physics.

signal hit_taken(info: HitInfo)
signal knocked_out(fighter: Fighter)
signal state_changed(state_name: StringName)

## Landing slower than this fraction of the fall speed is a light landing.
const SOFT_LANDING_RATIO := 0.5
## Stick tilt needed to walk or drift.
const MOVE_DEADZONE := 0.2
## How far beyond its body a fighter reaches for a ledge, in units.
const LEDGE_GRAB_REACH := 6.0
const LEDGE_REGRAB_COOLDOWN := 30
const LEDGE_INTANGIBILITY := 40
const RESPAWN_INVINCIBILITY := 120
## Downward speed applied while grounded so floor contact stays up to date.
const GROUND_STICK := -1.0
## Max air speed multiplier during helpless (special fall).
const HELPLESS_DRIFT := 0.75
## Tumbling into the ground faster than this bounces instead of knocking down.
const GROUND_BOUNCE_SPEED := 1.5
const BOUNCE_DAMPING := 0.8
## Soft platforms within this distance below the feet still count as underfoot (meters).
const PLATFORM_TOLERANCE := 0.1

@export var data: FighterData

## 1-based local player slot, used by the HUD.
var player_slot := 1
var controller: FighterController
var stage: Stage
var stats: FighterStats
var moveset: Moveset
var input := InputTracker.new()
var state: FighterState

## 1 when facing right, -1 when facing left.
var facing := 1
## The fighter's own velocity (walking, jumping, gravity, drift), units/frame.
var velocity_self := Vector2.ZERO
## Launch velocity from knockback, units/frame. Decays separately.
var velocity_knockback := Vector2.ZERO
## One-frame push from other fighters, units/frame.
var velocity_push := Vector2.ZERO
var grounded := false
var fast_falling := false
## Jumps spent since leaving the ground, including the ground jump.
var jumps_used := 0
var air_dodge_used := false
var percent := 0.0
var shield_hp := SmashFormulas.SHIELD_MAX
var hitlag_frames := 0
## Frames of intangibility from grabbing a ledge or respawning.
var intangible_frames := 0
var stale_queue := StaleMoveQueue.new()
var last_hit: HitInfo
var last_attacker: Fighter
var kos := 0
var falls := 0
## Frames simulated since this fighter was created.
var frame_count := 0
var ledge: StageLedge
var spawn_point := Vector3.ZERO

var model: FighterModel

var _hitlag_victim := false
var _has_pending_launch := false
var _pending_knockback := 0.0
var _pending_angle := 0.0
var _pending_tumble := false
var _sdi_multiplier := 1.0
var _landing_speed := 0.0
var _ledge_cooldown := 0
var _ledge_grabs_in_air := 0
var _floor_platform: SoftPlatform
var _drop_platform: SoftPlatform
var _ignored_platforms: Dictionary[SoftPlatform, bool] = {}
var _tech_window_until := -1
var _tech_lockout_until := -1

@onready var _collision: CollisionShape3D = %CollisionShape
@onready var _model_root: Node3D = %Model
@onready var _shield_bubble: MeshInstance3D = %ShieldBubble
@onready var _respawn_platform: MeshInstance3D = %RespawnPlatform
@onready var _debug_draw: FighterDebugDraw = %DebugDraw


func _ready() -> void:
	assert(data and data.stats and data.moveset, "Fighter needs FighterData with stats and a moveset.")
	stats = data.stats
	moveset = data.moveset
	collision_layer = PhysicsLayers.FIGHTER
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLATFORM
	floor_snap_length = 0.3

	var capsule := CapsuleShape3D.new()
	capsule.radius = Units.to_meters(stats.radius)
	capsule.height = Units.to_meters(stats.height)
	_collision.shape = capsule
	_collision.position.y = capsule.height / 2.0

	if data.model_scene:
		model = data.model_scene.instantiate() as FighterModel
		_model_root.add_child(model)
	var shield_material := _shield_bubble.material_override.duplicate() as StandardMaterial3D
	shield_material.albedo_color = Color(data.color, shield_material.albedo_color.a)
	_shield_bubble.material_override = shield_material
	_debug_draw.setup(self)

	state = IdleState.new(self)


## Places the fighter at [param point], ready to fight (standing if there is
## ground right below, falling otherwise).
func spawn(point: Vector3) -> void:
	spawn_point = point
	_reset_body()
	global_position = point
	reset_physics_interpolation()
	grounded = test_move(global_transform, Vector3.DOWN * 0.05)
	change_state(IdleState.new(self) if grounded else AirState.new(self))


#region Simulation

## Advances the fighter one frame. Called by [Match].
func tick() -> void:
	frame_count += 1
	input.feed(controller.poll(self) if controller else InputFrame.new())
	_track_tech_input()
	if hitlag_frames > 0:
		_tick_hitlag()
	else:
		_tick_timers()
		state.frame += 1
		state.update()
		_move()
		_try_grab_ledge()
		var attack := current_attack()
		if attack:
			attack.place_hitboxes()
	velocity_push = Vector2.ZERO


## Updates the model, shield bubble and debug shapes. Called after hits resolve.
func sync_visuals() -> void:
	var shielding := is_shielding()
	_shield_bubble.visible = shielding
	if shielding:
		var radius := Units.to_meters(stats.shield_radius * SmashFormulas.shield_scale(shield_hp))
		_shield_bubble.scale = Vector3.ONE * radius
		_shield_bubble.position = Vector3(0.0, Units.to_meters(stats.height) * 0.5, 0.0)
	_respawn_platform.visible = state is RespawnState
	if model:
		model.sync(self)
	_debug_draw.sync()


func change_state(new_state: FighterState) -> void:
	if state:
		state.exit()
	state = new_state
	state.enter()
	state_changed.emit(state.state_name())


## Returns to the neutral state for where the fighter is (idle or airborne) and
## runs its first frame right away, so buffered inputs come out on the first
## actionable frame.
func to_neutral() -> void:
	if grounded:
		change_state(IdleState.new(self))
	else:
		change_state(AirState.new(self))
	state.update()


func _tick_timers() -> void:
	if intangible_frames > 0:
		intangible_frames -= 1
	if _ledge_cooldown > 0:
		_ledge_cooldown -= 1
	if not state is ShieldState and not state is ShieldBreakState:
		shield_hp = minf(shield_hp + SmashFormulas.SHIELD_REGEN, SmashFormulas.SHIELD_MAX)


func _tick_hitlag() -> void:
	hitlag_frames -= 1
	if not _hitlag_victim:
		return
	var pulse := input.take_sdi_pulse()
	if pulse != Vector2.ZERO:
		var offset := pulse * SmashFormulas.SDI_DISTANCE * _sdi_multiplier
		move_and_collide(Vector3(offset.x, offset.y, 0.0) / Units.PER_METER)
		global_position.z = 0.0
	if hitlag_frames == 0 and _has_pending_launch:
		_launch()


func _move() -> void:
	if state.controls_position():
		return
	var total := velocity_self + velocity_knockback + velocity_push
	velocity_knockback = SmashFormulas.decay_launch(velocity_knockback)
	var was_grounded := grounded
	var landing_speed := -total.y
	if was_grounded and total.y <= 0.0:
		total.y = GROUND_STICK
	_update_platform_collisions(total.y)

	var previous := global_position
	velocity = Units.velocity_to_godot(total)
	move_and_slide()
	global_position.z = 0.0

	var on_floor := is_on_floor() and total.y <= 0.0
	if was_grounded and not on_floor and state.stops_at_edges():
		global_position = previous
		velocity_self.x = 0.0
		velocity_knockback.x = 0.0
		on_floor = true
	if is_on_ceiling() and total.y > 0.0:
		velocity_self.y = minf(velocity_self.y, 0.0)
		velocity_knockback.y = -velocity_knockback.y * BOUNCE_DAMPING if is_tumbling() else minf(velocity_knockback.y, 0.0)
	if is_on_wall():
		var normal_x := get_wall_normal().x
		if velocity_self.x * normal_x < 0.0:
			velocity_self.x = 0.0
		if velocity_knockback.x * normal_x < 0.0:
			velocity_knockback.x = -velocity_knockback.x * BOUNCE_DAMPING if is_tumbling() else 0.0

	_floor_platform = _find_floor_platform() if on_floor else null
	grounded = on_floor
	if grounded and not was_grounded:
		_land(landing_speed)
	elif was_grounded and not grounded:
		jumps_used = maxi(jumps_used, 1)
		state.on_left_ground()


func _land(speed: float) -> void:
	velocity_self.y = 0.0
	_landing_speed = speed
	jumps_used = 0
	air_dodge_used = false
	fast_falling = false
	_ledge_grabs_in_air = 0
	state.on_landed()


## Soft platforms are solid only while falling onto them from above, and not
## while dropping through or holding down in the air.
func _update_platform_collisions(vertical_speed: float) -> void:
	if not stage:
		return
	var feet := global_position.y
	var holding_down := not grounded and input.current.stick.y <= -InputTracker.PRESS_THRESHOLD
	for platform in stage.soft_platforms:
		var top := platform.get_top()
		if platform == _drop_platform and feet < top - PLATFORM_TOLERANCE:
			_drop_platform = null
		var solid := vertical_speed <= 0.0 and feet >= top - PLATFORM_TOLERANCE \
				and platform != _drop_platform and not holding_down
		_set_platform_ignored(platform, not solid)


func _set_platform_ignored(platform: SoftPlatform, ignored: bool) -> void:
	if ignored == _ignored_platforms.has(platform):
		return
	if ignored:
		add_collision_exception_with(platform)
		_ignored_platforms[platform] = true
	else:
		remove_collision_exception_with(platform)
		_ignored_platforms.erase(platform)


func _find_floor_platform() -> SoftPlatform:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y > 0.7 and collision.get_collider() is SoftPlatform:
			return collision.get_collider() as SoftPlatform
	return null


func _track_tech_input() -> void:
	if input.just_pressed(InputTracker.Btn.SHIELD) and frame_count >= _tech_lockout_until:
		_tech_window_until = frame_count + SmashFormulas.TECH_WINDOW
		_tech_lockout_until = frame_count + SmashFormulas.TECH_LOCKOUT

#endregion


#region Actions (used by states)

## Jump out of a grounded state: buffered jump button, or tap jump.
func try_jump() -> bool:
	var tapped := input.current.tap_jump and input.flicked_up()
	if not input.buffered(InputTracker.Btn.JUMP) and not tapped:
		return false
	input.consume(InputTracker.Btn.JUMP)
	change_state(JumpSquatState.new(self, tapped and not input.current.jump))
	return true


func try_double_jump() -> bool:
	if jumps_used >= stats.jump_count:
		return false
	var tapped := input.current.tap_jump and input.flicked_up()
	if not input.buffered(InputTracker.Btn.JUMP) and not tapped:
		return false
	input.consume(InputTracker.Btn.JUMP)
	jumps_used += 1
	fast_falling = false
	velocity_self.y = SmashFormulas.jump_velocity(stats.air_jump_height, stats.gravity)
	velocity_self.x = input.current.stick.x * stats.air_speed * stats.air_jump_x
	return true


## Leaves the ground at the end of jumpsquat.
func launch_jump(full_hop: bool) -> void:
	var height := stats.full_hop_height if full_hop else stats.short_hop_height
	velocity_self.y = SmashFormulas.jump_velocity(height, stats.gravity)
	var speed_x := velocity_self.x * stats.jump_momentum + input.current.stick.x * stats.jump_initial_x
	velocity_self.x = clampf(speed_x, -stats.jump_max_x, stats.jump_max_x)
	jumps_used = 1
	grounded = false
	change_state(AirState.new(self))


func try_ground_attack(from_run: bool = false) -> bool:
	if not input.buffered(InputTracker.Btn.ATTACK):
		return false
	input.consume(InputTracker.Btn.ATTACK)
	var slot := _ground_attack_slot(from_run)
	var move := moveset.get_move(slot)
	if not move:
		return false
	start_attack(slot, move)
	return true


func _ground_attack_slot(from_run: bool) -> StringName:
	var stick := input.attack_stick
	var horizontal := absf(stick.x) >= absf(stick.y)
	if input.attack_is_smash:
		if stick.length() < InputTracker.FLICK_FROM:
			return Moveset.FORWARD_SMASH
		if horizontal:
			facing = 1 if stick.x > 0.0 else -1
			return Moveset.FORWARD_SMASH
		return Moveset.UP_SMASH if stick.y > 0.0 else Moveset.DOWN_SMASH
	if from_run:
		return Moveset.DASH_ATTACK
	if stick.length() < 0.5:
		return Moveset.JAB
	if horizontal:
		facing = 1 if stick.x > 0.0 else -1
		return Moveset.FORWARD_TILT
	return Moveset.UP_TILT if stick.y > 0.0 else Moveset.DOWN_TILT


func try_aerial() -> bool:
	if not input.buffered(InputTracker.Btn.ATTACK):
		return false
	input.consume(InputTracker.Btn.ATTACK)
	var stick := input.attack_stick
	var slot := Moveset.NEUTRAL_AIR
	if stick.length() >= 0.5:
		if absf(stick.x) > absf(stick.y):
			slot = Moveset.FORWARD_AIR if stick.x * facing > 0.0 else Moveset.BACK_AIR
		else:
			slot = Moveset.UP_AIR if stick.y > 0.0 else Moveset.DOWN_AIR
	var move := moveset.get_move(slot)
	if not move:
		return false
	start_attack(slot, move)
	return true


func try_special() -> bool:
	if not input.buffered(InputTracker.Btn.SPECIAL):
		return false
	input.consume(InputTracker.Btn.SPECIAL)
	var stick := input.special_stick
	var slot := Moveset.NEUTRAL_SPECIAL
	if stick.y >= InputTracker.PRESS_THRESHOLD and stick.y >= absf(stick.x):
		slot = Moveset.UP_SPECIAL
	elif stick.y <= -InputTracker.PRESS_THRESHOLD and -stick.y >= absf(stick.x):
		slot = Moveset.DOWN_SPECIAL
	elif absf(stick.x) >= InputTracker.PRESS_THRESHOLD:
		slot = Moveset.SIDE_SPECIAL
	var move := moveset.get_move(slot)
	if not move:
		return false
	if slot == Moveset.SIDE_SPECIAL:
		facing = 1 if stick.x > 0.0 else -1
	start_attack(slot, move)
	return true


func try_shield() -> bool:
	if not input.current.shield:
		return false
	input.consume(InputTracker.Btn.SHIELD)
	change_state(ShieldState.new(self))
	return true


func try_air_dodge() -> bool:
	if air_dodge_used or not input.buffered(InputTracker.Btn.SHIELD):
		return false
	input.consume(InputTracker.Btn.SHIELD)
	air_dodge_used = true
	change_state(AirDodgeState.new(self, input.current.stick))
	return true


## Flick down on a soft platform to drop through it.
func try_drop_through() -> bool:
	if not grounded or not _floor_platform or not input.flicked_down():
		return false
	_drop_platform = _floor_platform
	grounded = false
	velocity_self.y = 0.0
	jumps_used = maxi(jumps_used, 1)
	change_state(AirState.new(self))
	return true


## Tap down while falling to fall at the fast fall speed.
func try_fast_fall() -> void:
	if fast_falling or grounded or velocity_self.y + velocity_knockback.y > 0.0:
		return
	if input.crossed_down():
		fast_falling = true
		velocity_self.y = -stats.fast_fall_speed()


func start_attack(slot: StringName, move: MoveData) -> void:
	change_state(AttackState.new(self, slot, move))


## Rolls toward [param direction] (1 right, -1 left) out of shield.
func start_roll(direction: int) -> void:
	if direction == facing:
		change_state(DodgeState.new(self, &"ForwardRoll", stats.forward_roll_frames,
				stats.forward_roll_intangible, stats.roll_distance, true))
	else:
		change_state(DodgeState.new(self, &"BackRoll", stats.back_roll_frames,
				stats.back_roll_intangible, -stats.roll_distance, false))


func start_spot_dodge() -> void:
	change_state(DodgeState.new(self, &"SpotDodge", stats.spot_dodge_frames,
			stats.spot_dodge_intangible, 0.0, false))


## Normal landing from the air: light or hard depending on falling speed.
func land() -> void:
	var light := _landing_speed < stats.fall_speed * SOFT_LANDING_RATIO
	change_state(LandingState.new(self, stats.soft_landing_frames if light else stats.hard_landing_frames))


## Landing while tumbling: tech if shield was pressed in time, bounce if
## spiked hard into the ground, otherwise get knocked down.
func land_from_tumble() -> void:
	if frame_count <= _tech_window_until:
		velocity_knockback = Vector2.ZERO
		velocity_self = Vector2.ZERO
		var x := input.current.stick.x
		if absf(x) >= InputTracker.PRESS_THRESHOLD:
			var distance := KnockdownState.TECH_ROLL_DISTANCE * signf(x) * facing
			change_state(DodgeState.new(self, &"TechRoll", KnockdownState.TECH_ROLL_FRAMES,
					KnockdownState.TECH_INTANGIBLE, distance, false))
		else:
			change_state(DodgeState.new(self, &"Tech", KnockdownState.TECH_FRAMES,
					KnockdownState.TECH_INTANGIBLE, 0.0, false))
		return
	if velocity_knockback.y < 0.0 and velocity_knockback.length() >= GROUND_BOUNCE_SPEED:
		velocity_knockback.y = -velocity_knockback.y * BOUNCE_DAMPING
		grounded = false
		return
	velocity_knockback = Vector2.ZERO
	change_state(KnockdownState.new(self))


func break_shield() -> void:
	shield_hp = 0.0
	change_state(ShieldBreakState.new(self))

#endregion


#region Movement physics (used by states)

func apply_traction(multiplier: float = 1.0) -> void:
	velocity_self.x = move_toward(velocity_self.x, 0.0, stats.traction * multiplier)


## Accelerates toward [param target] speed on the ground. Above the target in
## the same direction, traction slows the fighter instead.
func approach_ground_speed(target: float, acceleration: float) -> void:
	var speed := velocity_self.x
	if absf(speed) > absf(target) and signf(speed) == signf(target):
		velocity_self.x = move_toward(speed, target, stats.traction)
	else:
		velocity_self.x = move_toward(speed, target, acceleration)


func apply_gravity() -> void:
	if fast_falling:
		velocity_self.y = -stats.fast_fall_speed()
	else:
		velocity_self.y = maxf(velocity_self.y - stats.gravity, -stats.fall_speed)


## Smash air control: accelerate toward the stick's target speed; without
## input (or above max speed) slow down by air friction.
func apply_air_drift(max_speed_multiplier: float = 1.0, use_friction: bool = true) -> void:
	var x := input.current.stick.x
	var speed := velocity_self.x
	var max_speed := stats.air_speed * max_speed_multiplier
	if absf(x) < MOVE_DEADZONE:
		if use_friction:
			velocity_self.x = move_toward(speed, 0.0, stats.air_friction)
		return
	var target := max_speed * x
	if absf(speed) > absf(target) and signf(speed) == signf(x):
		velocity_self.x = move_toward(speed, target, stats.air_friction)
	else:
		velocity_self.x = move_toward(speed, target, stats.air_acceleration(absf(x)))

#endregion


#region Combat

## Called by [HitResolver] when one of this fighter's attacks connects.
func enter_hitlag(frames: int) -> void:
	if hitlag_frames <= 0:
		_hitlag_victim = false
	hitlag_frames = maxi(hitlag_frames, frames)


## Called by [HitResolver] when a hit lands on this fighter.
func receive_hit(info: HitInfo, hitbox: HitboxData, attacker: Fighter) -> void:
	last_hit = info
	last_attacker = attacker
	percent = minf(percent + info.damage, 999.0)
	release_ledge()
	air_dodge_used = false
	fast_falling = false
	input.clear_buffer()
	_has_pending_launch = true
	_pending_knockback = info.knockback
	_pending_angle = info.angle
	_pending_tumble = info.tumble
	_sdi_multiplier = hitbox.sdi_multiplier
	hitlag_frames = info.hitlag
	_hitlag_victim = true
	change_state(HitstunState.new(self, info.hitstun, info.tumble))
	if model:
		model.flash()
	if hitlag_frames == 0:
		_launch()
	hit_taken.emit(info)


## Called by [HitResolver] when a hit lands on this fighter's shield.
## [param damage] excludes the 1v1 multiplier.
func receive_shield_hit(info: HitInfo, hitbox: HitboxData, damage: float, attacker: Fighter) -> void:
	last_hit = info
	shield_hp -= SmashFormulas.shield_damage(damage, hitbox.shield_damage)
	hitlag_frames = maxi(hitlag_frames, info.hitlag)
	_hitlag_victim = false
	var stun := SmashFormulas.shieldstun_frames(damage, hitbox.shieldstun_multiplier)
	info.hitstun = stun
	var away := signf(global_position.x - attacker.global_position.x)
	if away == 0.0:
		away = -facing
	if state is ShieldState:
		(state as ShieldState).take_hit(stun, away * SmashFormulas.shield_pushback(stun))
	if shield_hp <= 0.0:
		break_shield()
	hit_taken.emit(info)


func _launch() -> void:
	_has_pending_launch = false
	var stick := input.current.stick
	var angle := SmashFormulas.apply_di(deg_to_rad(_pending_angle), stick)
	var speed_multiplier := SmashFormulas.launch_speed_influence(angle, stick) if _pending_tumble else 1.0
	var launch := SmashFormulas.launch_velocity(_pending_knockback, angle) * speed_multiplier
	if grounded and launch.y < 0.0:
		launch.y = -launch.y * BOUNCE_DAMPING if _pending_tumble else 0.0
	if launch.y > 0.0:
		grounded = false
	if absf(launch.x) > 0.01:
		facing = -1 if launch.x > 0.0 else 1
	velocity_knockback = launch
	velocity_self = Vector2.ZERO
	if last_hit:
		last_hit.final_angle = fposmod(rad_to_deg(angle), 360.0)
		last_hit.launch_speed = launch.length()


## Direction of the launch waiting for hitlag to end, or zero. Lets a
## [DummyController] choose its DI.
func get_pending_launch_direction() -> Vector2:
	if not _has_pending_launch:
		return Vector2.ZERO
	return Vector2.from_angle(deg_to_rad(_pending_angle))


func current_attack() -> AttackState:
	return state as AttackState


func get_active_hitboxes() -> Array[ActiveHitbox]:
	var attack := current_attack()
	return attack.active_hitboxes if attack else ([] as Array[ActiveHitbox])


func can_be_hit() -> bool:
	return not (state is KOState or state is RespawnState) and not is_intangible()


func is_intangible() -> bool:
	return intangible_frames > 0 or state.is_intangible()


func is_shielding() -> bool:
	var shield := state as ShieldState
	return shield != null and shield.is_raised()


func is_crouching() -> bool:
	return state is CrouchState


func is_tumbling() -> bool:
	if state is HitstunState:
		return (state as HitstunState).tumble
	var air := state as AirState
	return air != null and air.tumbling


## Hurtbox capsule axis (bottom, top) in units.
func get_hurt_segment() -> PackedVector2Array:
	var feet := Units.point_to_units(global_position)
	var height := stats.height
	if is_crouching():
		height *= stats.crouch_height_ratio
	elif state is KnockdownState:
		height *= 0.4
	var bottom := feet + Vector2(0.0, stats.radius)
	var top := feet + Vector2(0.0, maxf(height - stats.radius, stats.radius))
	return PackedVector2Array([bottom, top])


func get_hurt_radius() -> float:
	return stats.radius


## Shield bubble as (center x, center y, radius) in units; radius 0 when not shielding.
func get_shield_circle() -> Vector3:
	if not is_shielding():
		return Vector3.ZERO
	var feet := Units.point_to_units(global_position)
	return Vector3(feet.x, feet.y + stats.height * 0.5,
			stats.shield_radius * SmashFormulas.shield_scale(shield_hp))

#endregion


#region Ledges

func _try_grab_ledge() -> void:
	if not stage or grounded or _ledge_cooldown > 0 or not state.can_grab_ledge():
		return
	if input.current.stick.y <= -InputTracker.PRESS_THRESHOLD:
		return
	if velocity_self.y + velocity_knockback.y > 0.0 and not state.grabs_ledge_while_rising():
		return
	var feet := Units.point_to_units(global_position)
	for candidate in stage.ledges:
		var point := Units.point_to_units(candidate.global_position)
		var outward := (feet.x - point.x) * candidate.side
		if outward < -stats.radius or outward > stats.radius + LEDGE_GRAB_REACH:
			continue
		var above_feet := point.y - feet.y
		if above_feet < stats.height * 0.5 or above_feet > stats.height + LEDGE_GRAB_REACH:
			continue
		if candidate.occupant and candidate.occupant != self:
			candidate.occupant.get_trumped()
		grab_ledge(candidate)
		return


func grab_ledge(target: StageLedge) -> void:
	ledge = target
	target.occupant = self
	facing = -target.side
	velocity_self = Vector2.ZERO
	velocity_knockback = Vector2.ZERO
	fast_falling = false
	jumps_used = 1
	air_dodge_used = false
	# Only the first grab since touching the ground grants intangibility.
	intangible_frames = LEDGE_INTANGIBILITY if _ledge_grabs_in_air == 0 else 0
	_ledge_grabs_in_air += 1
	global_position = target.hang_position(stats)
	change_state(LedgeHangState.new(self))


## Lets go of the held ledge, if any. Briefly prevents regrabbing it.
func release_ledge() -> void:
	if not ledge:
		return
	if ledge.occupant == self:
		ledge.occupant = null
	ledge = null
	_ledge_cooldown = LEDGE_REGRAB_COOLDOWN


## Another fighter took the ledge (ledge trump): pop off it.
func get_trumped() -> void:
	var side := ledge.side if ledge else facing
	release_ledge()
	velocity_self = Vector2(side * 0.6, 0.0)
	change_state(AirState.new(self))

#endregion


#region Stocks

## Whether the fighter is outside [param blast_zone] (meters). The top blast
## zone only KOs fighters in hitstun, as in Smash.
func is_outside_blast_zone(blast_zone: Rect2) -> bool:
	var p := Vector2(global_position.x, global_position.y)
	if p.x < blast_zone.position.x or p.x > blast_zone.end.x or p.y < blast_zone.position.y:
		return true
	return p.y > blast_zone.end.y and state is HitstunState


func knock_out() -> void:
	falls += 1
	if last_attacker:
		last_attacker.kos += 1
	release_ledge()
	change_state(KOState.new(self))
	knocked_out.emit(self)


## Brings the fighter back on the revival platform at the top of the stage.
func respawn() -> void:
	_reset_body()
	global_position = stage.respawn_point() if stage else spawn_point + Vector3.UP * 5.0
	reset_physics_interpolation()
	change_state(RespawnState.new(self))


## Leaves the revival platform with a short invincibility.
func leave_respawn_platform() -> void:
	intangible_frames = RESPAWN_INVINCIBILITY
	jumps_used = 1
	change_state(AirState.new(self))


func set_body_enabled(enabled: bool) -> void:
	_collision.set_deferred(&"disabled", not enabled)
	visible = enabled


func _reset_body() -> void:
	release_ledge()
	set_body_enabled(true)
	percent = 0.0
	velocity_self = Vector2.ZERO
	velocity_knockback = Vector2.ZERO
	hitlag_frames = 0
	intangible_frames = 0
	shield_hp = SmashFormulas.SHIELD_MAX
	jumps_used = 0
	air_dodge_used = false
	fast_falling = false
	_has_pending_launch = false
	_drop_platform = null
	stale_queue.clear()
	last_attacker = null
	input.clear_buffer()

#endregion
