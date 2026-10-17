extends SceneTree
## Headless tests for the fighter simulation. Run with:
##   Godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if any check fails.
##
## Fighters are driven by scripted inputs on the real stage, so these tests
## check that stats produce the motion they describe (jump heights, speeds,
## fall speeds) and that combat follows the ported formulas.

const CAT := preload("res://fighters/roster/cat/cat.tres")
const BEAR := preload("res://fighters/roster/bear/bear.tres")
const STAGE := preload("res://stages/meadow/meadow.tscn")
const FIGHTER := preload("res://fighters/fighter.tscn")

var _checks := 0
var _failures: PackedStringArray = []


## Plays back inputs from a function of the frame number (starting at 1).
class ScriptedController extends FighterController:
	var script_fn: Callable
	var frame := 0

	func _init(fn: Callable) -> void:
		script_fn = fn

	func poll(_fighter: Fighter) -> InputFrame:
		frame += 1
		var input: InputFrame = script_fn.call(frame)
		return input if input else InputFrame.new()


## Minimal match loop: tick, resolve hits, check blast zones.
class TestWorld extends Node3D:
	var stage: Stage
	var fighters: Array[Fighter] = []

	func _physics_process(_delta: float) -> void:
		for fighter in fighters:
			fighter.tick()
		HitResolver.resolve(fighters, SmashFormulas.ONE_ON_ONE_DAMAGE)
		for fighter in fighters:
			if not fighter.state is KOState and fighter.is_outside_blast_zone(stage.blast_zone):
				fighter.knock_out()
			fighter.sync_visuals()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_formulas()
	_test_stale_queue()
	_test_input_tracker()
	await _test_jump_heights(CAT)
	await _test_jump_heights(BEAR)
	await _test_short_hop_airtime()
	await _test_ground_speeds(CAT)
	await _test_ground_speeds(BEAR)
	await _test_fall_speeds(CAT)
	await _test_soft_platforms()
	await _test_ledge_grab()
	await _test_knockback_and_weight()
	await _test_shield()
	await _test_ko_and_respawn()
	await _test_dummy()
	await _test_random_inputs()

	print("\n%d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAIL: ", failure)
	quit(1 if _failures.size() > 0 else 0)


#region Helpers

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s: expected %.3f ± %.3f, got %.3f" % [message, expected, tolerance, actual])


func _world() -> TestWorld:
	var world := TestWorld.new()
	root.add_child(world)
	world.stage = STAGE.instantiate() as Stage
	world.add_child(world.stage)
	return world


func _add_fighter(world: TestWorld, data: FighterData, position: Vector3, fn: Callable) -> Fighter:
	var fighter := FIGHTER.instantiate() as Fighter
	fighter.data = data
	fighter.stage = world.stage
	world.add_child(fighter)
	fighter.spawn(position)
	fighter.controller = ScriptedController.new(fn)
	world.fighters.append(fighter)
	return fighter


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _input(stick := Vector2.ZERO) -> InputFrame:
	var input := InputFrame.new()
	input.stick = stick
	input.tap_jump = false
	return input


func _feet_units(fighter: Fighter) -> float:
	return Units.to_units(fighter.global_position.y)

#endregion


func _test_formulas() -> void:
	# Knockback formula by hand: 12% hit, 50% after, weight 100, BKB 30, KBG 100.
	var expected := ((5.0 + 50.0 * 12.0 / 20.0) * (200.0 / 200.0) * 1.4 + 18.0) * 1.0 + 30.0
	_near(SmashFormulas.knockback(50.0, 12.0, 100.0, 100.0, 30.0), expected, 0.001, "knockback formula")
	# Heavier targets take less knockback.
	_check(SmashFormulas.knockback(80.0, 15.0, 130.0, 100.0, 20.0) < SmashFormulas.knockback(80.0, 15.0, 98.0, 100.0, 20.0),
			"heavier fighters take less knockback")
	# Set knockback ignores percent.
	_near(SmashFormulas.knockback(0.0, 5.0, 100.0, 100.0, 0.0, 10.0),
			SmashFormulas.knockback(150.0, 30.0, 100.0, 100.0, 0.0, 10.0), 0.001, "set knockback ignores percent and damage")
	_check(SmashFormulas.hitstun_frames(100.0) == 39, "hitstun at 100 knockback is 39 frames")
	_check(SmashFormulas.is_tumble(80.0) and not SmashFormulas.is_tumble(79.9), "tumble threshold is 80")
	_check(SmashFormulas.hitlag_frames(10.0) == 12, "hitlag for 10 damage is floor(10*0.65+6) = 12")
	_check(SmashFormulas.hitlag_frames(100.0) == SmashFormulas.MAX_HITLAG, "hitlag is capped at 30")
	_near(SmashFormulas.sakurai_angle(50.0, true), 0.0, 0.001, "Sakurai angle grounded, low knockback")
	_near(SmashFormulas.sakurai_angle(100.0, true), 38.0, 0.001, "Sakurai angle grounded, high knockback")
	_near(SmashFormulas.sakurai_angle(74.0, true), 19.0, 0.001, "Sakurai angle lerps between 60 and 88")
	_near(SmashFormulas.sakurai_angle(10.0, false), 38.0, 0.001, "Sakurai angle aerial")
	_near(SmashFormulas.apply_di(0.0, Vector2(0.0, 1.0)), SmashFormulas.DI_MAX_ANGLE, 0.0001, "full perpendicular DI")
	_near(SmashFormulas.apply_di(0.0, Vector2.RIGHT), 0.0, 0.0001, "parallel DI does nothing")
	_near(SmashFormulas.launch_speed_influence(deg_to_rad(90.0), Vector2(0.0, 1.0)), 1.0, 0.0001, "no LSI on vertical launches")
	_near(SmashFormulas.launch_speed_influence(deg_to_rad(40.0), Vector2(0.0, 1.0)), SmashFormulas.LSI_UP, 0.0001, "LSI up")
	_near(SmashFormulas.rage(150.0), 1.1, 0.0001, "max rage")
	_near(SmashFormulas.shield_scale(SmashFormulas.SHIELD_MAX), 1.0, 0.0001, "full shield scale")


func _test_stale_queue() -> void:
	var queue := StaleMoveQueue.new()
	_near(queue.multiplier(&"jab"), SmashFormulas.FRESHNESS_BONUS, 0.0001, "fresh move bonus")
	queue.push(&"jab")
	_near(queue.multiplier(&"jab"), 1.0 - 0.09, 0.0001, "once stale")
	queue.push(&"jab")
	_near(queue.multiplier(&"jab"), 1.0 - 0.09 - 0.08545, 0.0001, "twice stale")
	for i in 9:
		queue.push(&"ftilt")
	_near(queue.multiplier(&"jab"), SmashFormulas.FRESHNESS_BONUS, 0.0001, "queue holds 9 moves")


func _test_input_tracker() -> void:
	var tracker := InputTracker.new()
	tracker.feed(_input())
	tracker.feed(_input(Vector2(1.0, 0.0)))
	_check(tracker.flicked_x() == 1, "instant full tilt is a flick")
	tracker.feed(_input(Vector2(1.0, 0.0)))
	_check(tracker.flicked_x() == 0, "a held flick only registers once")

	var slow := InputTracker.new()
	for x: float in [0.0, 0.2, 0.4, 0.55, 0.7, 0.85, 1.0]:
		slow.feed(_input(Vector2(x, 0.0)))
		_check(slow.flicked_x() == 0, "slow tilt to %.2f is not a flick" % x)

	var buffered := InputTracker.new()
	var press := _input()
	press.attack = true
	buffered.feed(press)
	for i in InputTracker.BUFFER_FRAMES:
		buffered.feed(_input())
	_check(buffered.buffered(InputTracker.Btn.ATTACK), "press is buffered for 9 frames")
	buffered.feed(_input())
	_check(not buffered.buffered(InputTracker.Btn.ATTACK), "press expires after the buffer window")


func _test_jump_heights(data: FighterData) -> void:
	var stats := data.stats
	var name := data.display_name
	# Full hop: hold jump through jumpsquat.
	var world := _world()
	var fighter := _add_fighter(world, data, Vector3.ZERO, func(f: int) -> InputFrame:
		var input := _input()
		input.jump = f >= 5 and f < 20
		return input)
	await _frames(4)
	var ground := _feet_units(fighter)
	var peak := ground
	for i in 120:
		await physics_frame
		peak = maxf(peak, _feet_units(fighter))
	_near(peak - ground, stats.full_hop_height, 1.0, "%s full hop height" % name)
	world.free()

	# Short hop: release jump before jumpsquat ends.
	world = _world()
	fighter = _add_fighter(world, data, Vector3.ZERO, func(f: int) -> InputFrame:
		var input := _input()
		input.jump = f == 5
		return input)
	await _frames(4)
	ground = _feet_units(fighter)
	peak = ground
	for i in 90:
		await physics_frame
		peak = maxf(peak, _feet_units(fighter))
	_near(peak - ground, stats.short_hop_height, 1.0, "%s short hop height" % name)
	world.free()

	# Double jump at the apex of a full hop.
	world = _world()
	var apex := [0]
	fighter = _add_fighter(world, data, Vector3.ZERO, func(f: int) -> InputFrame:
		var input := _input()
		input.jump = (f >= 5 and f < 12) or (apex[0] > 0 and f >= apex[0] and f < apex[0] + 3)
		return input)
	await _frames(12)
	while fighter.velocity_self.y > 0.0:
		await physics_frame
	var before := _feet_units(fighter)
	apex[0] = (fighter.controller as ScriptedController).frame + 1
	peak = before
	var used_both := false
	for i in 120:
		await physics_frame
		peak = maxf(peak, _feet_units(fighter))
		used_both = used_both or fighter.jumps_used == 2
	_near(peak - before, stats.air_jump_height, 1.5, "%s double jump height" % name)
	_check(used_both, "%s used both jumps" % name)
	world.free()


func _test_short_hop_airtime() -> void:
	# ultimateframedata lists Mario's short hop at 40 frames; Cat uses Mario's stats.
	var world := _world()
	var fighter := _add_fighter(world, CAT, Vector3.ZERO, func(f: int) -> InputFrame:
		var input := _input()
		input.jump = f == 5
		return input)
	await _frames(4)
	var airborne := 0
	for i in 90:
		await physics_frame
		if not fighter.grounded:
			airborne += 1
		elif airborne > 0:
			break
	_near(airborne, 40.0, 2.0, "Cat short hop airtime (Mario: 40 frames)")
	world.free()

	# Full hops run longer than Ultimate's listed 56 frames (see docs/physics.md); report it.
	world = _world()
	fighter = _add_fighter(world, CAT, Vector3.ZERO, func(f: int) -> InputFrame:
		var input := _input()
		input.jump = f >= 5 and f < 20
		return input)
	await _frames(4)
	airborne = 0
	for i in 120:
		await physics_frame
		if not fighter.grounded:
			airborne += 1
		elif airborne > 0:
			break
	print("Cat full hop airtime: %d frames (Ultimate Mario: 56)" % airborne)
	world.free()


func _test_ground_speeds(data: FighterData) -> void:
	var stats := data.stats
	var name := data.display_name
	# Walk: tilt slowly to 0.75 so it isn't a flick.
	var world := _world()
	var fighter := _add_fighter(world, data, Vector3(-6.0, 0.0, 0.0), func(f: int) -> InputFrame:
		return _input(Vector2(minf(f * 0.1, 0.75), 0.0)))
	await _frames(40)
	_check(fighter.state is WalkState, "%s is walking after a slow tilt (%s)" % [name, fighter.state.state_name()])
	_near(fighter.velocity_self.x, stats.walk_speed * 0.75, 0.01, "%s walk speed at 0.75 tilt" % name)
	world.free()

	# Dash then run: flick to full tilt.
	world = _world()
	fighter = _add_fighter(world, data, Vector3(-7.0, 0.0, 0.0), func(f: int) -> InputFrame:
		return _input(Vector2(1.0 if f >= 3 else 0.0, 0.0)))
	await _frames(3)
	_check(fighter.state is DashState, "%s dashes on a flick" % name)
	_near(fighter.velocity_self.x, stats.initial_dash_speed, 0.001, "%s initial dash speed" % name)
	await _frames(stats.dash_frames + 30)
	_check(fighter.state is RunState, "%s runs after the dash (%s)" % [name, fighter.state.state_name()])
	_near(fighter.velocity_self.x, stats.run_speed, 0.001, "%s run speed" % name)
	world.free()


func _test_fall_speeds(data: FighterData) -> void:
	var stats := data.stats
	var world := _world()
	var fighter := _add_fighter(world, data, Vector3(0.0, 12.0, 0.0), func(f: int) -> InputFrame:
		return _input(Vector2(0.0, -1.0 if f >= 40 else 0.0)))
	await _frames(35)
	_near(fighter.velocity_self.y, -stats.fall_speed, 0.001, "%s terminal fall speed" % data.display_name)
	await _frames(6)
	_check(fighter.fast_falling, "%s fast falls on a down tap" % data.display_name)
	_near(fighter.velocity_self.y, -stats.fast_fall_speed(), 0.001, "%s fast fall speed" % data.display_name)
	world.free()


func _test_soft_platforms() -> void:
	var world := _world()
	var drop := [0]
	var fighter := _add_fighter(world, CAT, Vector3(-3.75, 0.0, 0.0), func(f: int) -> InputFrame:
		var input := _input()
		input.jump = f >= 5 and f < 15
		if drop[0] > 0 and f >= drop[0]:
			input.stick = Vector2(0.0, -1.0)
		return input)
	await _frames(100)
	var platform_top := world.stage.soft_platforms[0].get_top()
	_check(fighter.grounded, "Cat landed after jumping through the platform")
	_near(fighter.global_position.y, platform_top, 0.06, "Cat stands on the soft platform")
	drop[0] = (fighter.controller as ScriptedController).frame + 1
	await _frames(60)
	_check(fighter.grounded and fighter.global_position.y < 0.1, "Cat dropped through to the main platform (y %.2f)" % fighter.global_position.y)
	world.free()


func _test_ledge_grab() -> void:
	var world := _world()
	var climb := [0]
	var fighter := _add_fighter(world, CAT, Vector3(8.7, -0.9, 0.0), func(f: int) -> InputFrame:
		return _input(Vector2(-1.0 if climb[0] > 0 and f >= climb[0] else 0.0, 0.0)))
	await _frames(10)
	_check(fighter.state is LedgeHangState, "Cat grabs the ledge (%s)" % fighter.state.state_name())
	_check(fighter.is_intangible(), "ledge grab grants intangibility")
	climb[0] = (fighter.controller as ScriptedController).frame + 1
	await _frames(CAT.stats.ledge_getup_frames + LedgeHangState.GRAB_LAG + 10)
	_check(fighter.grounded and fighter.global_position.x < 8.0, "Cat climbs onto the stage (x %.2f)" % fighter.global_position.x)
	world.free()


## Cat forward smashes a target at 100%; compares the launch with the formulas
## and checks that the heavier Bear flies less far.
func _hit_with_forward_smash(target: FighterData, percent: float) -> Dictionary:
	var world := _world()
	var attacker := _add_fighter(world, CAT, Vector3(-0.5, 0.0, 0.0), func(f: int) -> InputFrame:
		var input := _input()
		input.smash = f == 5
		return input)
	var victim := _add_fighter(world, target, Vector3(0.45, 0.0, 0.0), func(_f: int) -> InputFrame:
		return _input())
	attacker.facing = 1
	victim.facing = -1
	await _frames(2)
	victim.percent = percent
	var hit_frame := -1
	for i in 40:
		await physics_frame
		if victim.last_hit:
			hit_frame = i
			break
	var info := victim.last_hit
	var result := {"hit": info != null}
	if info:
		await _frames(info.hitlag + 1)
		var start_x := victim.global_position.x
		await _frames(60)
		result["info"] = info
		result["distance"] = victim.global_position.x - start_x
		result["move"] = CAT.moveset.forward_smash
	world.free()
	return result


func _test_knockback_and_weight() -> void:
	var on_cat := await _hit_with_forward_smash(CAT, 100.0)
	var on_bear := await _hit_with_forward_smash(BEAR, 100.0)
	_check(on_cat["hit"] and on_bear["hit"], "forward smash connects")
	if not (on_cat["hit"] and on_bear["hit"]):
		return
	var info: HitInfo = on_cat["info"]
	var hitbox: HitboxData = (on_cat["move"] as MoveData).hitboxes[0]
	var fresh := SmashFormulas.FRESHNESS_BONUS
	var expected_damage := hitbox.damage * fresh * SmashFormulas.ONE_ON_ONE_DAMAGE
	_near(info.damage, expected_damage, 0.01, "forward smash damage (fresh, 1v1)")
	var expected_kb := SmashFormulas.knockback(100.0 + expected_damage,
			hitbox.damage * (1.0 + (fresh - 1.0) * SmashFormulas.STALENESS_KNOCKBACK_SHARE),
			CAT.stats.weight, hitbox.knockback_growth, hitbox.base_knockback)
	_near(info.knockback, expected_kb, 0.01, "knockback matches the formula")
	_check(info.hitstun == SmashFormulas.hitstun_frames(info.knockback), "hitstun matches the formula")
	_near(info.launch_speed, info.knockback * SmashFormulas.LAUNCH_SPEED_PER_KNOCKBACK, 0.01, "launch speed is 0.03 × knockback")
	_near(info.angle, SmashFormulas.SAKURAI_HIGH_ANGLE, 0.01, "Sakurai angle at high knockback")
	_check(info.tumble, "a 100% forward smash tumbles")
	var bear_info: HitInfo = on_bear["info"]
	_check(bear_info.knockback < info.knockback, "Bear (weight %.0f) takes less knockback than Cat (%.0f)" % [BEAR.stats.weight, CAT.stats.weight])
	_check(on_bear["distance"] < on_cat["distance"], "Bear travels less far (%.2f m vs %.2f m)" % [on_bear["distance"], on_cat["distance"]])


func _test_shield() -> void:
	var world := _world()
	var attacker := _add_fighter(world, BEAR, Vector3(-0.6, 0.0, 0.0), func(f: int) -> InputFrame:
		var input := _input()
		input.attack = f == 20
		return input)
	var defender := _add_fighter(world, CAT, Vector3(0.6, 0.0, 0.0), func(_f: int) -> InputFrame:
		var input := _input()
		input.shield = true
		return input)
	attacker.facing = 1
	defender.facing = -1
	await _frames(40)
	_check(defender.percent == 0.0, "shield blocks the damage")
	_check(defender.last_hit != null and defender.last_hit.shielded, "the hit registered on the shield")
	_check(defender.shield_hp < SmashFormulas.SHIELD_MAX - 5.0, "shield took damage (%.1f)" % defender.shield_hp)
	world.free()


func _test_ko_and_respawn() -> void:
	var world := _world()
	var attacker := _add_fighter(world, BEAR, Vector3(-0.9, 0.0, 0.0), func(f: int) -> InputFrame:
		var input := _input()
		input.smash = f == 5
		return input)
	var victim := _add_fighter(world, CAT, Vector3(0.5, 0.0, 0.0), func(_f: int) -> InputFrame:
		return _input())
	attacker.facing = 1
	await _frames(2)
	victim.percent = 160.0
	await _frames(240)
	_check(victim.falls == 1, "a 160%% forward smash KOs (falls %d)" % victim.falls)
	_check(attacker.kos == 1, "the attacker is credited with the KO")
	_check(victim.state is RespawnState or victim.state is AirState, "victim respawned (%s)" % victim.state.state_name())
	_check(victim.percent < 1.0, "respawn resets damage")
	world.free()


func _test_dummy() -> void:
	var world := _world()
	var dummy := _add_fighter(world, BEAR, Vector3(2.0, 0.0, 0.0), func(_f: int) -> InputFrame: return null)
	var controller := DummyController.new()
	controller.behavior = DummyController.Behavior.SHIELD
	dummy.controller = controller
	await _frames(10)
	_check(dummy.is_shielding(), "shield dummy holds shield (%s)" % dummy.state.state_name())
	controller.behavior = DummyController.Behavior.JUMP
	var left_ground := false
	for i in 120:
		await physics_frame
		left_ground = left_ground or not dummy.grounded
	_check(left_ground, "jump dummy jumps")
	world.free()


## Mashes random inputs on both fighters for a long time: nothing may break,
## positions stay finite, and fighters keep coming back after KOs.
func _test_random_inputs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var random_input := func(_f: int) -> InputFrame:
		var input := InputFrame.new()
		if rng.randf() < 0.7:
			input.stick = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).limit_length(1.0)
		input.attack = rng.randf() < 0.15
		input.special = rng.randf() < 0.05
		input.jump = rng.randf() < 0.1
		input.shield = rng.randf() < 0.1
		input.smash = rng.randf() < 0.03
		if rng.randf() < 0.03:
			input.cstick = Vector2.from_angle(rng.randf() * TAU)
		return input
	var world := _world()
	var a := _add_fighter(world, CAT, Vector3(-3.0, 0.0, 0.0), random_input)
	var b := _add_fighter(world, BEAR, Vector3(3.0, 0.0, 0.0), random_input)
	var states := {}
	for i in 6000:
		await physics_frame
		for fighter: Fighter in [a, b]:
			states[fighter.state.state_name()] = true
			var p := fighter.global_position
			if not (is_finite(p.x) and is_finite(p.y)):
				_check(false, "position became non-finite")
				world.free()
				return
	_check(a.percent > 0.0 or a.falls > 0, "random fight dealt damage")
	_check(states.size() >= 15, "random fight visited many states (%d: %s)" % [states.size(), ", ".join(states.keys())])
	print("random fight: %d states visited, falls %d/%d" % [states.size(), a.falls, b.falls])
	world.free()
