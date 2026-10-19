class_name Predict
## Trajectory prediction with a fighter's own stats, mirroring [Fighter]'s
## physics frame by frame: gravity, fall and fast fall speed, air drift and
## friction, launch decay, and landing on solid ground and soft platforms.
## Used for perception (where is the opponent now), hit queries, recovery
## plans, kill estimates and DI. Units and frames throughout.


## A fighter's physical state for a prediction (one per simulated path).
class Body:
	var position := Vector2.ZERO
	var velocity_self := Vector2.ZERO
	var velocity_knockback := Vector2.ZERO
	var fast_falling := false
	var grounded := false
	var stats: FighterStats

	func _init(p_stats: FighterStats, p_position: Vector2 = Vector2.ZERO,
			p_velocity_self: Vector2 = Vector2.ZERO, p_velocity_knockback: Vector2 = Vector2.ZERO) -> void:
		stats = p_stats
		position = p_position
		velocity_self = p_velocity_self
		velocity_knockback = p_velocity_knockback

	func copy() -> Body:
		var body := Body.new(stats, position, velocity_self, velocity_knockback)
		body.fast_falling = fast_falling
		body.grounded = grounded
		return body

	func velocity() -> Vector2:
		return velocity_self + velocity_knockback


static func body_from(snapshot: FighterSnapshot) -> Body:
	var body := Body.new(snapshot.stats, snapshot.position, snapshot.velocity_self, snapshot.velocity_knockback)
	body.grounded = snapshot.grounded
	body.fast_falling = snapshot.fast_falling
	return body


## [method Fighter.apply_gravity].
static func gravity(body: Body) -> void:
	var stats := body.stats
	if body.fast_falling:
		body.velocity_self.y = -stats.fast_fall_speed()
	else:
		body.velocity_self.y = maxf(body.velocity_self.y - stats.gravity, -stats.fall_speed)


## [method Fighter.apply_air_drift].
static func drift(body: Body, stick_x: float, max_speed_multiplier: float = 1.0, use_friction: bool = true) -> void:
	var stats := body.stats
	var speed := body.velocity_self.x
	if absf(stick_x) < Fighter.MOVE_DEADZONE:
		if use_friction:
			body.velocity_self.x = move_toward(speed, 0.0, stats.air_friction)
		return
	var target := stats.air_speed * max_speed_multiplier * stick_x
	if absf(speed) > absf(target) and signf(speed) == signf(stick_x):
		body.velocity_self.x = move_toward(speed, target, stats.air_friction)
	else:
		body.velocity_self.x = move_toward(speed, target, stats.air_acceleration(absf(stick_x)))


## Moves [param body] by its velocity for one frame and resolves collisions
## with [param stage] (null: no ground at all). Soft platforms catch falling
## bodies unless [param through_platforms]. Returns 1 on landing, -1 on hitting
## a ceiling, 2 on hitting a wall, 0 otherwise.
static func move(body: Body, stage: StageModel, through_platforms: bool = false) -> int:
	var total := body.velocity_self + body.velocity_knockback
	if body.velocity_knockback != Vector2.ZERO:
		body.velocity_knockback = SmashFormulas.decay_launch(body.velocity_knockback)
	var previous := body.position
	body.position += total
	if not stage:
		return 0
	var stats := body.stats
	# Far from every surface: nothing to collide with.
	var bounds := stage.bounds
	if body.position.x + stats.radius < bounds.position.x - 2.0 or body.position.x - stats.radius > bounds.end.x + 2.0 \
			or body.position.y > bounds.end.y + 2.0 and previous.y > bounds.end.y + 2.0 \
			or body.position.y + stats.height < bounds.position.y - 2.0:
		return 0
	var contact := stage.collide(body.position, previous, stats.radius, stats.height)
	if contact.z == 0.0 and total.y <= 0.0 and not through_platforms:
		for platform in stage.platforms:
			if body.position.x >= platform.x and body.position.x <= platform.y \
					and previous.y >= platform.z - 1.0 and body.position.y < platform.z:
				contact = Vector3(body.position.x, platform.z, 1.0)
				break
	if contact.z == 0.0:
		return 0
	body.position = Vector2(contact.x, contact.y)
	if contact.z == 1.0:
		body.grounded = true
		body.fast_falling = false
		body.velocity_self.y = 0.0
		body.velocity_knockback.y = 0.0
		return 1
	if contact.z == -1.0:
		body.velocity_self.y = minf(body.velocity_self.y, 0.0)
		body.velocity_knockback.y = minf(body.velocity_knockback.y, 0.0)
		return -1
	body.velocity_self.x = 0.0
	body.velocity_knockback.x = 0.0
	return 2


## One airborne frame with no new actions: gravity, drift, move.
## [param launched] matches hitstun, where air friction waits for the launch to end.
static func air_frame(body: Body, stage: StageModel, stick_x: float = 0.0, launched: bool = false) -> int:
	gravity(body)
	drift(body, stick_x, 1.0, not launched or body.velocity_knockback == Vector2.ZERO)
	return move(body, stage)


## Where the fighter in [param snapshot] will be over the next frames if it
## does nothing new. [param out] receives [param frames] + 1 positions (index
## 0 is now). Grounded movers keep their speed (up to the edges), everyone else
## slows down with traction; airborne fighters fall (with launch decay) until
## they land on a surface. A tight loop without wall or ceiling checks: this
## runs every frame for perception. Returns the body at the end.
static func trajectory(snapshot: FighterSnapshot, frames: int, stage: StageModel, out: PackedVector2Array) -> Body:
	out.resize(frames + 1)
	out[0] = snapshot.position
	var body := body_from(snapshot)
	var activity := snapshot.activity
	if activity == FighterSnapshot.Activity.LEDGE or activity == FighterSnapshot.Activity.RESPAWN \
			or activity == FighterSnapshot.Activity.LEDGE_ACTION or activity == FighterSnapshot.Activity.KO \
			or snapshot.grounded and body.velocity() == Vector2.ZERO:
		for i in range(1, frames + 1):
			out[i] = snapshot.position
		return body
	var launched := activity == FighterSnapshot.Activity.HITSTUN
	var moving := activity == FighterSnapshot.Activity.WALK or activity == FighterSnapshot.Activity.DASH \
			or activity == FighterSnapshot.Activity.RUN
	var stats := body.stats
	var gravity_step := stats.gravity
	var fall := -stats.fall_speed
	var fast := -stats.fast_fall_speed() if body.fast_falling else 0.0
	var friction := stats.air_friction
	var traction := stats.traction
	var px := body.position.x
	var py := body.position.y
	var vsx := body.velocity_self.x
	var vsy := body.velocity_self.y
	var vkx := body.velocity_knockback.x
	var vky := body.velocity_knockback.y
	var grounded := body.grounded
	var frozen := snapshot.hitlag
	var surfaces := stage.surfaces if stage else PackedVector3Array()
	for i in range(1, frames + 1):
		if frozen > 0:
			frozen -= 1
		elif grounded:
			if not moving:
				vsx = move_toward(vsx, 0.0, traction)
			px += vsx + vkx
			if stage and absf(py - stage.main_top) < 1.0:
				px = clampf(px, stage.main_left, stage.main_right)
		else:
			vsy = fast if fast < 0.0 else maxf(vsy - gravity_step, fall)
			if not launched or vkx == 0.0 and vky == 0.0:
				vsx = move_toward(vsx, 0.0, friction)
			var dx := vsx + vkx
			var dy := vsy + vky
			if vkx != 0.0 or vky != 0.0:
				var speed := sqrt(vkx * vkx + vky * vky)
				if speed <= SmashFormulas.LAUNCH_DECAY:
					vkx = 0.0
					vky = 0.0
				else:
					var keep := (speed - SmashFormulas.LAUNCH_DECAY) / speed
					vkx *= keep
					vky *= keep
			var ny := py + dy
			px += dx
			if dy <= 0.0:
				for surface in surfaces:
					if px >= surface.x and px <= surface.y and py >= surface.z - 1.0 and ny < surface.z:
						ny = surface.z
						grounded = true
						vsy = 0.0
						vky = 0.0
						break
			py = ny
		out[i] = Vector2(px, py)
	body.position = Vector2(px, py)
	body.velocity_self = Vector2(vsx, vsy)
	body.velocity_knockback = Vector2(vkx, vky)
	body.grounded = grounded
	return body


## Advances [param snapshot] by [param frames] in place: position and velocity
## by [method trajectory], and every timer by the elapsed frames.
static func extrapolate(snapshot: FighterSnapshot, frames: int, stage: StageModel, scratch: PackedVector2Array) -> void:
	if frames <= 0:
		return
	var body := trajectory(snapshot, frames, stage, scratch)
	snapshot.position = body.position
	snapshot.velocity_self = body.velocity_self
	snapshot.velocity_knockback = body.velocity_knockback
	snapshot.grounded = body.grounded
	snapshot.state_frame += maxi(frames - snapshot.hitlag, 0)
	snapshot.hitlag = maxi(snapshot.hitlag - frames, 0)
	snapshot.actionable_in = maxi(snapshot.actionable_in - frames, 0)
	snapshot.intangible_left = maxi(snapshot.intangible_left - frames, 0)
	snapshot.frame += frames


## Frames until [param body] lands, falling with no input, or -1 within [param limit].
static func frames_to_land(body: Body, stage: StageModel, limit: int, launched: bool = false) -> int:
	var sim := body.copy()
	for i in range(1, limit + 1):
		if air_frame(sim, stage, 0.0, launched) == 1:
			return i
	return -1


## [method frames_to_land] for the fighter in [param snapshot], with the
## perception loop (no wall checks). Cheap enough to call every frame.
static func frames_to_land_fast(snapshot: FighterSnapshot, stage: StageModel, limit: int, scratch: PackedVector2Array) -> int:
	if snapshot.grounded:
		return 0
	trajectory(snapshot, limit, stage, scratch)
	for i in range(1, limit + 1):
		if scratch[i].y == scratch[i - 1].y and scratch[i].y < scratch[0].y + 0.001 and _on_surface(scratch[i], stage):
			return i
	return -1


static func _on_surface(point: Vector2, stage: StageModel) -> bool:
	for surface in stage.surfaces:
		if point.x >= surface.x and point.x <= surface.y and absf(point.y - surface.z) < 0.001:
			return true
	return false


## Simulates a launch at [param launch_velocity] for [param hitstun] frames and
## then a free fall of up to [param tail] frames. Returns the smallest margin to
## the blast zone along the way (negative: KO). The top line only counts while
## in hitstun, as in Smash.
static func launch_margin(stats: FighterStats, position: Vector2, launch_velocity: Vector2, hitstun: int,
		stage: StageModel, tail: int = 30) -> float:
	var body := Body.new(stats, position, Vector2.ZERO, launch_velocity)
	var margin := INF
	var zone := stage.blast_zone
	for i in hitstun + tail:
		if air_frame(body, stage, 0.0, true) == 1 and body.velocity_knockback == Vector2.ZERO:
			break
		var p := body.position
		var side := minf(p.x - zone.position.x, zone.end.x - p.x)
		var bottom := p.y - zone.position.y
		var top := zone.end.y - p.y if i < hitstun else INF
		margin = minf(margin, minf(minf(side, bottom), top))
		if margin < 0.0:
			return margin
	return margin


## Initial launch velocity for a hit, as [method Fighter._launch] computes it
## (DI from [param stick], LSI on tumble launches).
static func launch_velocity(knockback: float, angle_degrees: float, stick: Vector2, tumble: bool) -> Vector2:
	var angle := SmashFormulas.apply_di(deg_to_rad(angle_degrees), stick)
	var speed := SmashFormulas.launch_speed_influence(angle, stick) if tumble else 1.0
	return SmashFormulas.launch_velocity(knockback, angle) * speed


## Feet positions of a fighter jumping from the ground at [param position] now:
## jumpsquat, then a full or short hop holding [param stick_x], with an aerial
## started on the frame after leaving the ground (so no gravity that frame).
## Index 0 is now; [param frames] + 1 positions.
static func jump_path(stats: FighterStats, position: Vector2, velocity_x: float, full_hop: bool,
		stick_x: float, frames: int, stage: StageModel) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames + 1)
	var body := Body.new(stats, position)
	var vx := velocity_x
	var squat := stats.jumpsquat_frames
	out[0] = position
	for i in range(1, frames + 1):
		if i <= squat:
			vx = move_toward(vx, 0.0, stats.traction)
			body.position.x += vx
		elif i == squat + 1:
			var speed_x := vx * stats.jump_momentum + stick_x * stats.jump_initial_x
			var height := stats.full_hop_height if full_hop else stats.short_hop_height
			body.velocity_self = Vector2(clampf(speed_x, -stats.jump_max_x, stats.jump_max_x),
					SmashFormulas.jump_velocity(height, stats.gravity))
			move(body, stage, true)
		elif i == squat + 2:
			move(body, stage, true)
		else:
			gravity(body)
			drift(body, stick_x)
			if move(body, stage, body.velocity_self.y > 0.0) == 1:
				for j in range(i, frames + 1):
					out[j] = body.position
				return out
		out[i] = body.position
	return out


## Feet positions of an airborne fighter drifting with [param stick_x], index 0 now.
static func air_path(stats: FighterStats, position: Vector2, velocity_self: Vector2, velocity_knockback: Vector2,
		fast_falling: bool, stick_x: float, frames: int, stage: StageModel) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames + 1)
	var body := Body.new(stats, position, velocity_self, velocity_knockback)
	body.fast_falling = fast_falling
	out[0] = position
	for i in range(1, frames + 1):
		gravity(body)
		drift(body, stick_x)
		if move(body, stage, body.velocity().y > 0.0) == 1:
			for j in range(i, frames + 1):
				out[j] = body.position
			return out
		out[i] = body.position
	return out
