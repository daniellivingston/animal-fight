class_name AiDi
## Directional influence choices for CPUs and the training dummy: DI and LSI
## (the stick held on the frame hitlag ends) and Smash DI pulses during hitlag.

## The training dummy's fixed DI settings.
enum Mode { NONE, SURVIVAL, COMBO }

## Stick candidates for [method best]: perpendicular in and out, plus up and down
## for launch speed influence.
const _CANDIDATES: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071)]


## The dummy's DI: the stick perpendicular to the launch. "Survival" bends it
## upward (or toward the stage on vertical launches) to live longer; "Combo"
## does the opposite. [param x] is the fighter's x position (any unit).
static func fixed(mode: Mode, launch: Vector2, x: float) -> Vector2:
	if mode == Mode.NONE or launch == Vector2.ZERO:
		return Vector2.ZERO
	var perpendicular := Vector2(-launch.y, launch.x)
	var toward_safety := perpendicular.y
	if absf(toward_safety) < 0.2:
		# Near-vertical launch: drift toward the stage center instead.
		toward_safety = perpendicular.x * -signf(x)
	if toward_safety < 0.0:
		perpendicular = -perpendicular
	return perpendicular if mode == Mode.SURVIVAL else -perpendicular


## The stick that keeps [param fighter] furthest from the blast zones for its
## pending launch, by simulating each candidate with [Predict].
static func best(fighter: Fighter, stage: StageModel) -> Vector2:
	var direction := fighter.get_pending_launch_direction()
	var knockback := fighter.get_pending_knockback()
	if direction == Vector2.ZERO or knockback <= 0.0:
		return Vector2.ZERO
	var angle := rad_to_deg(direction.angle())
	var tumble := SmashFormulas.is_tumble(knockback)
	var hitstun := SmashFormulas.hitstun_frames(knockback)
	var position := Units.point_to_units(fighter.global_position)
	var best_stick := Vector2.ZERO
	var best_margin := -INF
	for stick: Vector2 in [Vector2.ZERO] + _CANDIDATES:
		var launch := Predict.launch_velocity(knockback, angle, stick, tumble)
		if fighter.grounded and launch.y < 0.0:
			launch.y = -launch.y * Fighter.BOUNCE_DAMPING if tumble else 0.0
		var margin := Predict.launch_margin(fighter.stats, position, launch, hitstun, stage, 20)
		if margin > best_margin + 0.01:
			best_margin = margin
			best_stick = stick
	return best_stick


## Combo DI: away from the attacker and slightly down, which makes follow-ups
## harder at low percents.
static func away(fighter: Fighter, attacker_x: float) -> Vector2:
	var away_x := signf(Units.to_units(fighter.global_position.x) - attacker_x)
	if away_x == 0.0:
		away_x = -fighter.facing
	return Vector2(away_x * 0.9, -0.3).normalized()


## SDI direction during hitlag: away from the attacker, or toward the stage
## when near a blast zone.
static func sdi_direction(fighter: Fighter, attacker_x: float, stage: StageModel) -> Vector2:
	var position := Units.point_to_units(fighter.global_position)
	if stage.blast_margin(position) < 60.0 or stage.is_offstage(position):
		return Vector2(signf(stage.center_x() - position.x), 1.0).normalized()
	var away_x := signf(position.x - attacker_x)
	if away_x == 0.0:
		away_x = -fighter.facing
	return Vector2(away_x, 0.0)
