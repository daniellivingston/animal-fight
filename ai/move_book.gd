class_name MoveBook
extends RefCounted
## The [MoveProfile]s of one [Moveset], built on first use and cached per
## moveset resource. Answers "which of my moves reach there, and how fast".
## Moves added to a moveset later (specials, grabs) are picked up automatically.

const GROUND_SLOTS: Array[StringName] = [Moveset.JAB, Moveset.FORWARD_TILT, Moveset.UP_TILT,
		Moveset.DOWN_TILT, Moveset.FORWARD_SMASH, Moveset.UP_SMASH, Moveset.DOWN_SMASH,
		Moveset.NEUTRAL_SPECIAL, Moveset.SIDE_SPECIAL, Moveset.UP_SPECIAL, Moveset.DOWN_SPECIAL]
const AIR_SLOTS: Array[StringName] = [Moveset.NEUTRAL_AIR, Moveset.FORWARD_AIR, Moveset.BACK_AIR,
		Moveset.UP_AIR, Moveset.DOWN_AIR, Moveset.NEUTRAL_SPECIAL, Moveset.SIDE_SPECIAL,
		Moveset.UP_SPECIAL, Moveset.DOWN_SPECIAL]

## How a move is started, which decides its delay and the attacker's path.
enum Approach { STAND, TURN, DASH, SHORT_HOP, FULL_HOP, AIR, OUT_OF_SHIELD }


## One way to hit the target: a move, how to start it, and when it connects.
class Option:
	var profile: MoveProfile
	var approach := Approach.STAND
	var facing := 1
	## Frames from now until the hitbox touches the target.
	var frames := 0
	## Frames before the move itself starts.
	var delay := 0
	## Stick x held for drift (aerials) or steering (specials).
	var drift := 0.0

	func _init(p_profile: MoveProfile, p_approach: Approach, p_facing: int, p_frames: int, p_delay: int,
			p_drift: float = 0.0) -> void:
		profile = p_profile
		approach = p_approach
		facing = p_facing
		frames = p_frames
		delay = p_delay
		drift = p_drift


static var _cache: Dictionary[Moveset, MoveBook] = {}

var moveset: Moveset
var profiles: Array[MoveProfile] = []
## Moves that start from the ground (tilts, smashes, jab, specials). Dash attack is separate.
var ground: Array[MoveProfile] = []
## Moves that start in the air (aerials, specials).
var air: Array[MoveProfile] = []
var dash_attack: MoveProfile
var up_special: MoveProfile
## Startup of the fastest grounded move with a hitbox.
var fastest_startup := 99

var _by_slot: Dictionary[StringName, MoveProfile] = {}
var _air_extent := 0.0
var _reach_by_startup: Dictionary[int, float] = {}


static func of(p_moveset: Moveset) -> MoveBook:
	var book: MoveBook = _cache.get(p_moveset)
	if not book:
		book = MoveBook.new(p_moveset)
		_cache[p_moveset] = book
	return book


func _init(p_moveset: Moveset) -> void:
	moveset = p_moveset
	for slot: StringName in GROUND_SLOTS + [Moveset.DASH_ATTACK] + AIR_SLOTS:
		if _by_slot.has(slot):
			continue
		var move := moveset.get_move(slot)
		if not move:
			continue
		var profile := MoveProfile.new(slot, move)
		_by_slot[slot] = profile
		profiles.append(profile)
	for slot in GROUND_SLOTS:
		if _by_slot.has(slot):
			ground.append(_by_slot[slot])
			if _by_slot[slot].has_hitboxes():
				fastest_startup = mini(fastest_startup, _by_slot[slot].startup)
	for slot in AIR_SLOTS:
		if _by_slot.has(slot):
			air.append(_by_slot[slot])
	dash_attack = _by_slot.get(Moveset.DASH_ATTACK)
	up_special = _by_slot.get(Moveset.UP_SPECIAL)
	for profile in air:
		_air_extent = maxf(_air_extent, profile.max_extent)


func get_profile(slot: StringName) -> MoveProfile:
	return _by_slot.get(slot)


## Forward reach (units past the feet) of the grounded moves that come out
## within [param max_startup] frames. How far this fighter threatens.
func quick_reach(max_startup: int) -> float:
	if _reach_by_startup.has(max_startup):
		return _reach_by_startup[max_startup]
	var best := 0.0
	for profile in ground:
		if profile.has_hitboxes() and profile.startup <= max_startup and not profile.ends_in_helpless:
			best = maxf(best, profile.reach.end.x)
	_reach_by_startup[max_startup] = best
	return best


## The hitboxes of [param profile] on [param move_frame] in the world, for an
## attacker with feet at [param feet] facing [param facing]: (x, y, radius) each.
static func world_hitboxes(profile: MoveProfile, move_frame: int, feet: Vector2, facing: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if move_frame < profile.startup or move_frame > profile.active_end:
		return result
	for hitbox: HitboxData in profile.hitboxes_by_frame[move_frame]:
		result.append(Vector3(feet.x + hitbox.offset.x * facing, feet.y + hitbox.offset.y, hitbox.radius))
	return result


## Every way this fighter ([param me], seen as it is now) can hit [param target]
## within [param within] frames, given the target's predicted feet
## [param target_path] (index 0 is now). [param approaches] is a bitmask of
## [enum Approach] values (1 << approach) to consider; [param allowed] filters
## profiles. The hurt capsule and the attacker's own path use the same rules as
## [HitResolver] and [Predict].
func moves_hitting(me: FighterSnapshot, target: FighterSnapshot, target_path: PackedVector2Array,
		within: int, stage: StageModel, approaches: int, allowed: Callable, paths: Dictionary = {}) -> Array[Option]:
	var result: Array[Option] = []
	var horizon := mini(within, target_path.size() - 1)
	var toward := 1 if target_path[horizon].x >= me.position.x else -1
	var height := target.hurt_height
	var radius := target.hurt_radius
	var stats := me.stats
	var left := stage.main_left if me.grounded else -INF
	var right := stage.main_right if me.grounded else INF
	var no_path := PackedVector2Array()
	# Closest the target gets horizontally, to skip moves that can't reach.
	var min_gap := INF
	for i in horizon + 1:
		min_gap = minf(min_gap, absf(target_path[i].x - me.position.x))
	min_gap -= radius
	var air_travel := maxf(stats.air_speed, stats.jump_max_x) * horizon

	if approaches & (1 << Approach.STAND | 1 << Approach.TURN | 1 << Approach.OUT_OF_SHIELD):
		var shielding := approaches & (1 << Approach.OUT_OF_SHIELD) != 0
		for profile in ground:
			if profile.max_extent < min_gap or not allowed.call(profile):
				continue
			if shielding:
				# Out of shield: up special straight away, jump-cancelled up smash
				# one frame later. Anything else needs the shield dropped first.
				var delay := -1
				if profile.slot == Moveset.UP_SPECIAL:
					delay = 0
				elif profile.slot == Moveset.UP_SMASH:
					delay = 1
				if delay < 0:
					continue
				var t := profile.first_contact(me.position, no_path, me.facing, delay, target_path, height, radius, left, right)
				if t >= 0 and t <= horizon:
					result.append(Option.new(profile, Approach.OUT_OF_SHIELD, me.facing, t, delay))
				continue
			var facing := toward if profile.turns_to_stick else me.facing
			var t := profile.first_contact(me.position, no_path, facing, 0, target_path, height, radius, left, right)
			if t >= 0 and t <= horizon:
				result.append(Option.new(profile, Approach.STAND, facing, t, 0))
			elif not profile.turns_to_stick and approaches & (1 << Approach.TURN) and facing != toward:
				t = profile.first_contact(me.position, no_path, toward, 1, target_path, height, radius, left, right)
				if t >= 0 and t <= horizon:
					result.append(Option.new(profile, Approach.TURN, toward, t, 1))

	if approaches & (1 << Approach.DASH) and dash_attack and dash_attack.max_extent + stats.initial_dash_speed * 2.0 >= min_gap \
			and allowed.call(dash_attack):
		# A neutral frame, the dash frame, then the attack's first frame at dash speed.
		var origin := me.position + Vector2(toward * stats.initial_dash_speed * 2.0, 0.0)
		origin.x = clampf(origin.x, left, right)
		var t := dash_attack.first_contact(origin, no_path, toward, 2, target_path, height, radius, left, right)
		if t >= 0 and t <= horizon:
			result.append(Option.new(dash_attack, Approach.DASH, toward, t, 2))

	if approaches & (1 << Approach.SHORT_HOP | 1 << Approach.FULL_HOP | 1 << Approach.OUT_OF_SHIELD) \
			and _air_extent + air_travel >= min_gap:
		var squat := stats.jumpsquat_frames + 1
		var hops: Array[bool] = []
		if approaches & (1 << Approach.SHORT_HOP | 1 << Approach.OUT_OF_SHIELD):
			hops.append(false)
		if approaches & (1 << Approach.FULL_HOP):
			hops.append(true)
		for full in hops:
			for drift: float in [float(toward), 0.0]:
				var key := Vector3(1.0 if full else 0.0, drift, horizon)
				if not paths.has(key):
					paths[key] = Predict.jump_path(stats, me.position, me.velocity_self.x, full, drift, horizon, stage)
				var path: PackedVector2Array = paths[key]
				var presses: Array[int] = [squat]
				if full:
					presses = [squat, squat + 6, squat + 12]
				for press in presses:
					for profile in air:
						if not profile.is_aerial or not allowed.call(profile):
							continue
						var facing := me.facing
						var t := profile.first_contact(me.position, path, facing, press, target_path, height, radius)
						if t >= 0 and t <= horizon:
							var approach := Approach.FULL_HOP if full else Approach.SHORT_HOP
							if approaches & (1 << Approach.OUT_OF_SHIELD):
								approach = Approach.OUT_OF_SHIELD
							result.append(Option.new(profile, approach, facing, t, press, drift))

	if approaches & (1 << Approach.AIR) and _air_extent + air_travel >= min_gap:
		for drift: float in [float(toward), 0.0]:
			var key := Vector3(2.0, drift, horizon)
			if not paths.has(key):
				paths[key] = Predict.air_path(stats, me.position, me.velocity_self, me.velocity_knockback,
						me.fast_falling, drift, horizon, stage)
			var path: PackedVector2Array = paths[key]
			for profile in air:
				if not allowed.call(profile):
					continue
				var t := profile.first_contact(me.position, path, me.facing, 0, target_path, height, radius)
				if t >= 0 and t <= horizon:
					result.append(Option.new(profile, Approach.AIR, me.facing, t, 0, drift))
	return result
