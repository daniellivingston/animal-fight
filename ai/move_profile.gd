class_name MoveProfile
extends RefCounted
## What a CPU knows about one move, derived from its [MoveData] (Smash's ATKD
## files, built automatically): when its hitboxes come out and end, where they
## reach, how the move carries the fighter, how safe it is and how hard it hits.
## Reach and offsets are relative to the feet with +x forward, in units.

enum Category { JAB, TILT, DASH_ATTACK, SMASH, AERIAL, SPECIAL }

const AERIAL_SLOTS: Array[StringName] = [Moveset.NEUTRAL_AIR, Moveset.FORWARD_AIR, Moveset.BACK_AIR,
		Moveset.UP_AIR, Moveset.DOWN_AIR]
const SMASH_SLOTS: Array[StringName] = [Moveset.FORWARD_SMASH, Moveset.UP_SMASH, Moveset.DOWN_SMASH]
const TILT_SLOTS: Array[StringName] = [Moveset.FORWARD_TILT, Moveset.UP_TILT, Moveset.DOWN_TILT]
const SPECIAL_SLOTS: Array[StringName] = [Moveset.NEUTRAL_SPECIAL, Moveset.SIDE_SPECIAL,
		Moveset.UP_SPECIAL, Moveset.DOWN_SPECIAL]

var slot: StringName
var move: MoveData
var category := Category.JAB
## First and last active frame.
var startup := 0
var active_end := 0
var total := 0
var landing_lag := 0
## Bounding box of every hitbox.
var reach := Rect2()
## Active hitboxes per move frame (index = frame), lowest id first.
var hitboxes_by_frame: Array[Array] = []
## The fighter's displacement from the move's own motion at each frame (index =
## frame), starting from standing still, without gravity.
var displacement := PackedVector2Array()
var is_aerial := false
var is_smash := false
var is_special := false
## The stick sets facing when the move starts (forward tilt, forward smash, side special).
var turns_to_stick := false
var chargeable := false
var ends_in_helpless := false
var ledge_grab_frame := 0
## The hardest-hitting hitbox (most knockback at 100%).
var strongest: HitboxData
## Largest hitbox damage.
var damage := 0.0
## Furthest any hitbox gets from the starting feet horizontally, motion included.
var max_extent := 0.0
## Frames of endlag after the last active frame.
var whiff_lag := 0
## Frame advantage when the first hitbox is shielded (negative: the attacker
## recovers later than the shielder).
var shield_advantage := 0


func _init(p_slot: StringName, p_move: MoveData) -> void:
	slot = p_slot
	move = p_move
	is_aerial = AERIAL_SLOTS.has(slot)
	is_smash = SMASH_SLOTS.has(slot)
	is_special = SPECIAL_SLOTS.has(slot)
	turns_to_stick = slot == Moveset.FORWARD_TILT or slot == Moveset.FORWARD_SMASH or slot == Moveset.SIDE_SPECIAL
	if is_aerial:
		category = Category.AERIAL
	elif is_smash:
		category = Category.SMASH
	elif is_special:
		category = Category.SPECIAL
	elif TILT_SLOTS.has(slot):
		category = Category.TILT
	elif slot == Moveset.DASH_ATTACK:
		category = Category.DASH_ATTACK
	total = move.total_frames
	landing_lag = move.landing_lag
	chargeable = move.charge_frame > 0
	ends_in_helpless = move.ends_in_helpless
	ledge_grab_frame = move.ledge_grab_frame

	startup = 1 << 20
	var first_damage := 0.0
	var strongest_knockback := -1.0
	for hitbox in move.hitboxes:
		var box := Rect2(hitbox.offset - Vector2.ONE * hitbox.radius, Vector2.ONE * hitbox.radius * 2.0)
		reach = box if reach.size == Vector2.ZERO else reach.merge(box)
		if hitbox.start_frame < startup:
			startup = hitbox.start_frame
			first_damage = hitbox.damage
		active_end = maxi(active_end, hitbox.end_frame)
		damage = maxf(damage, hitbox.damage)
		var knockback := SmashFormulas.knockback(100.0, hitbox.damage, 100.0, hitbox.knockback_growth,
				hitbox.base_knockback, hitbox.set_knockback)
		if knockback > strongest_knockback:
			strongest_knockback = knockback
			strongest = hitbox
	if move.hitboxes.is_empty():
		startup = 0
	hitboxes_by_frame.resize(active_end + 1)
	for f in range(startup, active_end + 1):
		hitboxes_by_frame[f] = move.active_hitboxes(f)
	whiff_lag = total - active_end
	shield_advantage = SmashFormulas.shieldstun_frames(first_damage) - (total - startup)

	# After the motion, grounded moves slide to a stop and rising ones arc
	# down, with Mario's traction, gravity and fall speed standing in for the
	# fighter's own (movesets are shared).
	var defaults := FighterStats.new()
	displacement.resize(total + 1)
	var offset := Vector2.ZERO
	var velocity := Vector2.ZERO
	var airborne := move.motion_velocity.y > 0.0
	for f in range(2, total + 1):
		if move.is_in_motion(f):
			velocity = move.motion_velocity
		elif airborne:
			velocity.x = move_toward(velocity.x, 0.0, defaults.air_friction)
			velocity.y = maxf(velocity.y - defaults.gravity, -defaults.fall_speed)
		else:
			velocity.x = move_toward(velocity.x, 0.0, defaults.traction)
		offset += velocity
		displacement[f] = offset
	var travel := 0.0
	for f in range(startup, mini(active_end, total) + 1):
		travel = maxf(travel, absf(displacement[f].x))
	max_extent = maxf(absf(reach.position.x), absf(reach.end.x)) + travel


func has_hitboxes() -> bool:
	return not move.hitboxes.is_empty()


## Frames the move takes on whiff, including landing lag for aerials.
func commitment() -> int:
	return total + (landing_lag if is_aerial else 0)


## Knockback of [member strongest] on a target with [param weight] at
## [param percent] (before the hit), with stale multiplier [param stale].
func knockback_at(percent: float, weight: float, stale: float = 1.0, charge: float = 1.0,
		damage_ratio: float = SmashFormulas.ONE_ON_ONE_DAMAGE) -> float:
	var hitbox := strongest
	var base := hitbox.damage * charge
	var dealt := base * stale * damage_ratio
	var knockback_damage := base * (1.0 + (stale - 1.0) * SmashFormulas.STALENESS_KNOCKBACK_SHARE)
	return SmashFormulas.knockback(percent + dealt, knockback_damage, weight, hitbox.knockback_growth,
			hitbox.base_knockback, hitbox.set_knockback)


## Launch angle of [member strongest] in degrees, for an attacker facing [param facing].
func launch_angle(knockback: float, target_grounded: bool, facing: int) -> float:
	var angle := float(strongest.angle)
	if strongest.angle == SmashFormulas.SAKURAI_ANGLE:
		angle = SmashFormulas.sakurai_angle(knockback, target_grounded)
	if facing * (-1 if strongest.reverse else 1) < 0:
		angle = 180.0 - angle
	return angle


## Whether the move's strongest hit would KO [param target] from where it is,
## without DI. Uses [Predict] to follow the launch to the blast zone.
func kills(target: FighterSnapshot, facing: int, stage: StageModel, stale: float = 1.0, charge: float = 1.0) -> bool:
	if not has_hitboxes():
		return false
	var knockback := knockback_at(target.percent, target.stats.weight, stale, charge)
	# Cheap reject: even with no gravity the launch can't cover the distance.
	var speed := knockback * SmashFormulas.LAUNCH_SPEED_PER_KNOCKBACK
	if speed * speed / (2.0 * SmashFormulas.LAUNCH_DECAY) < stage.blast_margin(target.position) - 5.0 \
			and speed * speed / (2.0 * SmashFormulas.LAUNCH_DECAY) < stage.blast_zone.end.y - target.position.y - 5.0:
		return false
	var angle := launch_angle(knockback, target.grounded, facing)
	var tumble := SmashFormulas.is_tumble(knockback)
	var launch := Predict.launch_velocity(knockback, angle, Vector2.ZERO, tumble)
	if target.grounded and launch.y < 0.0:
		launch.y = -launch.y * Fighter.BOUNCE_DAMPING if tumble else 0.0
	return Predict.launch_margin(target.stats, target.position, launch, SmashFormulas.hitstun_frames(knockback), stage) < 0.0


## The first frame (counted from now) on which a hitbox of this move touches
## the target, or -1. The move starts after [param delay] frames; the attacker's
## feet are at [param attacker_path][t] on frame t if given, otherwise at
## [param origin] plus the move's own motion. [param target_path][t] is the
## target's feet on frame t.
func first_contact(origin: Vector2, attacker_path: PackedVector2Array, facing: int, delay: int,
		target_path: PackedVector2Array, hurt_height: float, hurt_radius: float, edge_left: float = -INF,
		edge_right: float = INF) -> int:
	if not has_hitboxes():
		return -1
	var bottom_offset := hurt_radius
	var top_offset := maxf(hurt_height - hurt_radius, hurt_radius)
	for f in range(startup, active_end + 1):
		var t := delay + f
		if t < 1:
			continue
		if t >= target_path.size():
			return -1
		var feet: Vector2
		if not attacker_path.is_empty():
			feet = attacker_path[mini(t, attacker_path.size() - 1)]
		else:
			var shift := displacement[f]
			feet = Vector2(clampf(origin.x + shift.x * facing, edge_left, edge_right), origin.y + shift.y)
		var target := target_path[t]
		for hitbox: HitboxData in hitboxes_by_frame[f]:
			var center := feet + Vector2(hitbox.offset.x * facing, hitbox.offset.y)
			var dy := center.y - clampf(center.y, target.y + bottom_offset, target.y + top_offset)
			var dx := center.x - target.x
			var reach_sum := hitbox.radius + hurt_radius
			if dx * dx + dy * dy <= reach_sum * reach_sum:
				return t
	return -1
