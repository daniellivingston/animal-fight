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
const ROSTER_DIR := "res://fighters/roster/"
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


## Minimal match loop: tick, resolve hits, check blast zones, capture what
## CPUs see.
class TestWorld extends Node3D:
	var stage: Stage
	var fighters: Array[Fighter] = []
	var ai_world: AiWorld

	func _physics_process(_delta: float) -> void:
		for fighter in fighters:
			fighter.tick()
		HitResolver.resolve(fighters, SmashFormulas.ONE_ON_ONE_DAMAGE)
		for fighter in fighters:
			if not fighter.state is KOState and fighter.is_outside_blast_zone(stage.blast_zone):
				fighter.knock_out()
			fighter.sync_visuals()
		ai_world.capture()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_formulas()
	_test_stale_queue()
	_test_input_tracker()
	await _test_roster()
	await _test_short_hop_airtime()
	await _test_soft_platforms()
	await _test_ledge_grab()
	await _test_knockback_and_weight()
	await _test_shield()
	await _test_ko_and_respawn()
	await _test_dummy()
	await _test_random_inputs()
	await _test_cpu_perception_delay()
	await _test_cpu_walks_toward_opponent()
	await _test_cpu_macros()
	_test_move_profiles()
	await _test_predict_trajectory()
	await _test_hit_query_agreement()
	await _test_cpu_determinism_and_inputs()
	await _test_cpu_reaction()
	await _test_cpu_punish()
	await _test_cpu_no_self_destructs()
	await _test_cpu_recovery_grid()
	await _test_recovery_fidelity()
	await _test_cpu_di()

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
	world.ai_world = AiWorld.new(world.stage, world.fighters)
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


## Adds a CPU-controlled fighter.
func _add_cpu(world: TestWorld, data: FighterData, position: Vector3, level: int,
		mode: CpuController.Mode = CpuController.Mode.FIGHT, seed: int = 1) -> CpuController:
	var fighter := _add_fighter(world, data, position, func(_f: int) -> InputFrame: return null)
	var cpu := CpuController.new(level, mode)
	cpu.setup(world.ai_world, seed, data.cpu_profile)
	fighter.controller = cpu
	return cpu


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


## Every character in fighters/roster/ (<name>/<name>.tres): complete model, and
## stats that produce their motion. (match.tscn can't be loaded here: it needs
## the GameInput autoload, which --script runs don't load.)
func _test_roster() -> void:
	var match_text := FileAccess.get_file_as_string("res://match/match.tscn")
	var roster: Array[FighterData] = []
	for dir in DirAccess.get_directories_at(ROSTER_DIR):
		var path := ROSTER_DIR + "%s/%s.tres" % [dir, dir]
		if ResourceLoader.exists(path):
			roster.append(load(path) as FighterData)
			_check(match_text.contains('path="%s"' % path), "%s is selectable (listed in match.tscn)" % dir)
	_check(roster.size() >= 2, "found %d roster characters" % roster.size())
	for data in roster:
		_test_model(data)
		await _test_jump_heights(data)
		await _test_ground_speeds(data)
		await _test_fall_speeds(data)


func _test_model(data: FighterData) -> void:
	var model := data.model_scene.instantiate() if data.model_scene else null
	_check(model is FighterModel, "%s has a FighterModel scene" % data.display_name)
	var animated := model as AnimatedFighterModel
	if animated:
		var players := animated.find_children("*", "AnimationPlayer", true, false)
		_check(players.size() == 1, "%s model has one AnimationPlayer" % data.display_name)
		var player := players.front() as AnimationPlayer
		for anim in animated.animation_names():
			_check(player != null and player.has_animation(anim), "%s model has animation %s" % [data.display_name, anim])
	if model:
		model.free()


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


## The training dummy is a CPU in one of Smash's training modes.
func _test_dummy() -> void:
	var world := _world()
	var controller := _add_cpu(world, BEAR, Vector3(2.0, 0.0, 0.0), 3, CpuController.Mode.SHIELD)
	var dummy := world.fighters[0]
	await _frames(10)
	_check(dummy.is_shielding(), "shield dummy holds shield (%s)" % dummy.state.state_name())
	controller.set_mode(CpuController.Mode.JUMP)
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


#region CPU

## A CPU in STAND mode running one forced plan; returns its fighter.
func _macro_fighter(world: TestWorld, position: Vector3, builder: Callable, data: FighterData = CAT) -> Fighter:
	var cpu := _add_cpu(world, data, position, 9, CpuController.Mode.STAND)
	cpu.params.timing_error = 0.0
	var fighter := world.fighters.back() as Fighter
	cpu.force_plan(builder)
	return fighter


## Runs [param frames] frames and returns every state name visited, in order.
func _visited_states(fighter: Fighter, frames: int) -> PackedStringArray:
	var visited: PackedStringArray = []
	for i in frames:
		await physics_frame
		var name := String(fighter.state.state_name())
		if visited.is_empty() or visited[visited.size() - 1] != name:
			visited.append(name)
	return visited


## The CPU sees its opponent [member CpuDifficulty.Params.reaction_frames] late
## (or later, with jitter), and at level 1 (no extrapolation) exactly where it was.
func _test_cpu_perception_delay() -> void:
	var world := _world()
	var mover := _add_fighter(world, CAT, Vector3(-3.0, 0.0, 0.0), func(f: int) -> InputFrame:
		return _input(Vector2(1.0 if f >= 30 and f < 70 else 0.0, 0.0)))
	var cpu := _add_cpu(world, BEAR, Vector3(5.0, 0.0, 0.0), 1, CpuController.Mode.STAND)
	var history: Array[Vector2] = []
	var reaction := cpu.params.reaction_frames
	var too_fresh := 0
	var wrong_position := 0
	var max_delay := 0
	for i in 150:
		await physics_frame
		history.append(Units.point_to_units(mover.global_position))
		if i < reaction + 5:
			continue
		if cpu.reaction_delay < reaction:
			too_fresh += 1
		max_delay = maxi(max_delay, cpu.reaction_delay)
		# At poll time the world had i captures; the view is reaction_delay older.
		var seen_index := i - 1 - cpu.reaction_delay
		if seen_index >= 0 and cpu.target.position.distance_to(history[seen_index]) > 0.01:
			wrong_position += 1
	_check(too_fresh == 0, "CPU never sees the opponent sooner than its reaction time (%d too fresh)" % too_fresh)
	_check(max_delay <= reaction + cpu.params.reaction_jitter, "reaction delay stays within reaction + jitter (max %d)" % max_delay)
	_check(wrong_position == 0, "level 1 sees the opponent exactly where it was (%d mismatches)" % wrong_position)
	world.free()


func _test_cpu_walks_toward_opponent() -> void:
	var world := _world()
	var target := _add_fighter(world, CAT, Vector3(-4.5, 0.0, 0.0), func(_f: int) -> InputFrame: return _input())
	_add_cpu(world, BEAR, Vector3(4.5, 0.0, 0.0), 5)
	var cpu_fighter := world.fighters[1]
	var start := absf(cpu_fighter.global_position.x - target.global_position.x)
	await _frames(150)
	var gap := absf(cpu_fighter.global_position.x - target.global_position.x)
	_check(gap < start - 1.5 or target.percent > 0.0, "a CPU moves toward its opponent (%.1f m -> %.1f m)" % [start, gap])
	world.free()


## Each InputPlan macro reaches the fighter state it's for, including the
## input gotchas: walking never dashes, tilts aren't smashes, a short-hop up
## air isn't a jump-cancelled up smash, a released fast fall still grabs the
## ledge, and a single tech press only techs inside the window.
func _test_cpu_macros() -> void:
	var stats := CAT.stats
	var world := _world()
	var fighter := _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void: p.walk(1, 30))
	var visited := await _visited_states(fighter, 25)
	_check(visited.has("Walk") and not visited.has("Dash") and not visited.has("Run"), "walk macro walks (%s)" % ", ".join(visited))
	world.free()

	world = _world()
	fighter = _macro_fighter(world, Vector3(-3.0, 0.0, 0.0), func(p: InputPlan) -> void: p.dash(1, 20))
	await _frames(2)
	_check(fighter.state is DashState, "dash macro dashes on its second frame (%s)" % fighter.state.state_name())
	await _frames(stats.dash_frames + 4)
	_check(fighter.state is RunState, "held dash turns into a run (%s)" % fighter.state.state_name())
	world.free()

	for full: bool in [true, false]:
		world = _world()
		fighter = _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void:
			if full:
				p.full_hop()
			else:
				p.short_hop())
		await _frames(1)
		var ground := _feet_units(fighter)
		var peak := ground
		for i in 100:
			await physics_frame
			peak = maxf(peak, _feet_units(fighter))
		var height := stats.full_hop_height if full else stats.short_hop_height
		_near(peak - ground, height, 1.0, "%s macro height" % ("full hop" if full else "short hop"))
		world.free()

	for slot: StringName in [Moveset.UP_AIR, Moveset.FORWARD_AIR, Moveset.BACK_AIR, Moveset.NEUTRAL_AIR, Moveset.DOWN_AIR]:
		world = _world()
		fighter = _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void: p.short_hop_aerial(slot, 1))
		var used := &""
		var peak := 0.0
		var ground := _feet_units(fighter)
		for i in 40:
			await physics_frame
			peak = maxf(peak, _feet_units(fighter) - ground)
			var attack := fighter.current_attack()
			if attack and used == &"":
				used = attack.slot
				_check(not fighter.grounded, "short-hop %s comes out in the air" % slot)
		_check(used == slot, "short-hop aerial macro does %s (got %s)" % [slot, used])
		# The aerial's first frame skips gravity, so it peaks a little above a plain short hop.
		_check(peak < (stats.short_hop_height + stats.full_hop_height) * 0.5, "short-hop %s is a short hop (%.1f)" % [slot, peak])
		world.free()

	for slot: StringName in [Moveset.FORWARD_TILT, Moveset.UP_TILT, Moveset.DOWN_TILT, Moveset.JAB]:
		world = _world()
		fighter = _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void: p.tilt(slot, 1))
		await _frames(2)
		var attack := fighter.current_attack()
		_check(attack != null and attack.slot == slot, "tilt macro does %s (got %s)" % [slot, attack.slot if attack else &"none"])
		world.free()

	for slot: StringName in [Moveset.FORWARD_SMASH, Moveset.UP_SMASH, Moveset.DOWN_SMASH]:
		world = _world()
		var charge_frame := CAT.moveset.get_move(slot).charge_frame
		fighter = _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void: p.smash_attack(slot, -1, 20, charge_frame))
		await _frames(1)
		var attack := fighter.current_attack()
		_check(attack != null and attack.slot == slot, "smash macro does %s" % slot)
		await _frames(charge_frame + 5)
		_check(attack != null and attack.is_charging(), "smash macro charges %s" % slot)
		_check(slot != Moveset.FORWARD_SMASH or fighter.facing == -1, "forward smash macro turns to its direction")
		world.free()

	# Fast fall, released in time: still grabs the ledge.
	world = _world()
	fighter = _macro_fighter(world, Vector3(9.3, 1.0, 0.0), func(p: InputPlan) -> void:
		p.wait_until(InputPlan.Until.FALLING, 30)
		p.fast_fall())
	var fast := false
	for i in 40:
		await physics_frame
		fast = fast or fighter.fast_falling
		if fighter.state is LedgeHangState:
			break
	_check(fast, "fast fall macro fast falls")
	_check(fighter.state is LedgeHangState, "released fast fall still grabs the ledge (%s)" % fighter.state.state_name())
	var cpu := fighter.controller as CpuController
	for option: Array in [["climb", "LedgeClimb"], ["roll", "LedgeRoll"], ["jump", "LedgeJump"], ["drop", "Air"]]:
		var w := _world()
		var hanger := _macro_fighter(w, Vector3(8.7, -0.9, 0.0), func(p: InputPlan) -> void: p.wait(10))
		await _frames(10)
		var kind: String = option[0]
		(hanger.controller as CpuController).force_plan(func(p: InputPlan) -> void: _option_macro(p, kind))
		var states := await _visited_states(hanger, 12)
		_check(states.has(option[1]), "ledge %s macro (%s)" % [kind, ", ".join(states)])
		w.free()
	world.free()

	# Drop through a soft platform, double jump.
	world = _world()
	fighter = _macro_fighter(world, Vector3(-3.75, 2.75, 0.0), func(p: InputPlan) -> void:
		p.wait(5)
		p.drop_through())
	await _frames(20)
	_check(fighter.global_position.y < 2.4, "drop-through macro falls through the platform (y %.2f)" % fighter.global_position.y)
	world.free()
	world = _world()
	fighter = _macro_fighter(world, Vector3(0.0, 3.0, 0.0), func(p: InputPlan) -> void:
		p.wait(3)
		p.double_jump(0.0))
	await _frames(2)
	var jumps_before := fighter.jumps_used
	await _frames(6)
	_check(fighter.jumps_used == jumps_before + 1 and fighter.velocity_self.y > 0.0, "double jump macro jumps (%d)" % fighter.jumps_used)
	world.free()

	# Specials, aerials, air dodge.
	world = _world()
	fighter = _macro_fighter(world, Vector3(0.0, 3.0, 0.0), func(p: InputPlan) -> void:
		p.wait(2)
		p.special(Vector2(0.0, 1.0), 0.0, 10))
	await _frames(4)
	_check(fighter.current_attack() != null and fighter.current_attack().slot == Moveset.UP_SPECIAL, "up special macro")
	world.free()
	world = _world()
	fighter = _macro_fighter(world, Vector3(0.0, 3.0, 0.0), func(p: InputPlan) -> void:
		p.wait(2)
		p.aerial(Moveset.BACK_AIR, 1))
	await _frames(4)
	_check(fighter.current_attack() != null and fighter.current_attack().slot == Moveset.BACK_AIR, "aerial macro")
	world.free()
	world = _world()
	fighter = _macro_fighter(world, Vector3(0.0, 3.0, 0.0), func(p: InputPlan) -> void:
		p.wait(2)
		p.air_dodge(Vector2(1.0, 0.0)))
	await _frames(4)
	_check(fighter.state is AirDodgeState, "air dodge macro (%s)" % fighter.state.state_name())
	world.free()

	# Shield, rolls, spot dodge.
	for option: Array in [["shield", "Shield"], ["ground roll", "ForwardRoll"], ["back roll", "BackRoll"], ["spot dodge", "SpotDodge"]]:
		world = _world()
		var kind: String = option[0]
		fighter = _macro_fighter(world, Vector3.ZERO, func(p: InputPlan) -> void: _option_macro(p, kind))
		fighter.facing = 1
		var states := await _visited_states(fighter, 10)
		_check(states.has(option[1]), "%s macro (%s)" % [kind, ", ".join(states)])
		world.free()

	await _test_tech_macro()


static func _option_macro(p: InputPlan, kind: String) -> void:
	match kind:
		"climb":
			p.ledge_climb(-1)
		"roll":
			p.ledge_roll()
		"jump":
			p.ledge_jump(-1)
		"drop":
			p.ledge_drop(1)
		"shield":
			p.shield(20)
		"ground roll":
			p.roll(1)
		"back roll":
			p.roll(-1)
		"spot dodge":
			p.spot_dodge()


## A single shield press inside the tech window techs; one pressed 12+ frames
## before landing misses.
func _test_tech_macro() -> void:
	var landing := -1
	for press_before: int in [-1, 5, 13]:
		var world := _world()
		var fighter := _macro_fighter(world, Vector3(0.0, 2.0, 0.0), func(p: InputPlan) -> void: p.wait(1))
		await _frames(1)
		fighter.change_state(HitstunState.new(fighter, 35, true))
		fighter.velocity_knockback = Vector2(0.0, -1.0)
		var cpu := fighter.controller as CpuController
		if press_before >= 0:
			cpu.force_plan(func(p: InputPlan) -> void: p.tech(maxi(landing - press_before - 1, 0), 0.0))
		else:
			cpu.force_plan(func(p: InputPlan) -> void: p.wait(60))
		var states: PackedStringArray = []
		for i in 60:
			await physics_frame
			if landing < 0 and fighter.grounded:
				landing = i + 1
			var name := String(fighter.state.state_name())
			if states.is_empty() or states[states.size() - 1] != name:
				states.append(name)
		if press_before == 5:
			_check(states.has("Tech"), "a tech press 5 frames before landing techs (%s)" % ", ".join(states))
		elif press_before == 13:
			_check(not states.has("Tech") and states.has("Knockdown"), "a tech press 13 frames early misses (%s)" % ", ".join(states))
		world.free()


## Move profiles match the hand-checked moveset data.
func _test_move_profiles() -> void:
	var cat := MoveBook.of(CAT.moveset)
	var fsmash := cat.get_profile(Moveset.FORWARD_SMASH)
	_check(fsmash.startup == 15 and fsmash.active_end == 16, "Cat forward smash is active on frames 15-16 (%d-%d)" % [fsmash.startup, fsmash.active_end])
	_near(fsmash.reach.end.x, 15.0, 0.01, "Cat forward smash reaches x = 15")
	_check(fsmash.is_smash and fsmash.chargeable and fsmash.category == MoveProfile.Category.SMASH, "forward smash is a chargeable smash")
	_check(fsmash.shield_advantage < -cat.fastest_startup - 10, "forward smash is unsafe on shield (%d)" % fsmash.shield_advantage)
	var jab := cat.get_profile(Moveset.JAB)
	_check(jab.startup == 2 and cat.fastest_startup == 2, "Cat's fastest move is the frame-2 jab")
	var dash := cat.dash_attack
	_check(dash.displacement[12] .x > 15.0, "dash attack carries the fighter forward (%.1f)" % dash.displacement[12].x)
	var up_special := cat.up_special
	_check(up_special.ends_in_helpless and up_special.ledge_grab_frame == 10, "Cat up special ends helpless and grabs ledges from frame 10")
	var bear := MoveBook.of(BEAR.moveset)
	_check(bear.get_profile(Moveset.FORWARD_SMASH).startup == 19, "Bear forward smash starts on frame 19")
	_check(MoveBook.of(CAT.moveset) == cat, "move books are cached per moveset")
	var reach := RecoveryPlanner.special_reach(BEAR.moveset.up_special, BEAR.stats)
	_check(reach.y > 25.0 and reach.x > 30.0, "Bear's up special rises and steers far (%.0f, %.0f)" % [reach.x, reach.y])


## Predict follows a launched fighter to within a unit after 20 frames.
func _test_predict_trajectory() -> void:
	var world := _world()
	var fighter := _add_fighter(world, CAT, Vector3(-2.0, 3.0, 0.0), func(_f: int) -> InputFrame: return _input())
	await _frames(2)
	fighter.change_state(HitstunState.new(fighter, 40, true))
	fighter.velocity_knockback = Vector2(2.2, 1.6)
	fighter.velocity_self = Vector2.ZERO
	var snapshot := FighterSnapshot.new()
	snapshot.capture(fighter, 0, 0, world.fighters)
	var path := PackedVector2Array()
	Predict.trajectory(snapshot, 20, world.ai_world.stage_model, path)
	await _frames(20)
	var actual := Units.point_to_units(fighter.global_position)
	_check(path[20].distance_to(actual) <= 1.0, "predicted launch position after 20 frames is within 1 unit (off by %.2f)" % path[20].distance_to(actual))

	# Falling, landing on the stage.
	var body := Predict.Body.new(CAT.stats, Vector2(0.0, 30.0))
	var land := Predict.frames_to_land(body, world.ai_world.stage_model, 120)
	fighter.change_state(AirState.new(fighter))
	fighter.global_position = Vector3(0.0, 3.0, 0.0)
	fighter.velocity_self = Vector2.ZERO
	fighter.velocity_knockback = Vector2.ZERO
	var frames := 0
	for i in 120:
		await physics_frame
		frames += 1
		if fighter.grounded:
			break
	_check(absi(frames - land) <= 1, "predicted landing frame matches (%d vs %d)" % [land, frames])
	world.free()


## The hit query's "will hit" agrees with HitResolver in randomized
## close-range trials: grounded moves (and dash attacks) at standing targets.
func _test_hit_query_agreement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var slots: Array[StringName] = [Moveset.JAB, Moveset.FORWARD_TILT, Moveset.UP_TILT, Moveset.DOWN_TILT,
			Moveset.FORWARD_SMASH, Moveset.UP_SMASH, Moveset.DOWN_SMASH, Moveset.DASH_ATTACK]
	var trials := 64
	var agree := 0
	var hits := 0
	for trial in trials:
		var attacker_data: FighterData = CAT if trial % 2 == 0 else BEAR
		var target_data: FighterData = BEAR if trial % 3 == 0 else CAT
		var slot := slots[trial % slots.size()]
		var gap := rng.randf_range(-2.6, 2.6)
		var world := _world()
		var cpu := _add_cpu(world, attacker_data, Vector3(0.0, 0.0, 0.0), 9, CpuController.Mode.STAND)
		var attacker := world.fighters[0]
		var target := _add_fighter(world, target_data, Vector3(gap, 0.0, 0.0), func(_f: int) -> InputFrame: return _input())
		attacker.facing = 1 if rng.randf() < 0.7 else -1
		await _frames(2)
		var me := FighterSnapshot.new()
		me.capture(attacker, 0, world.ai_world.frame, world.fighters)
		var them := FighterSnapshot.new()
		them.capture(target, 1, world.ai_world.frame, world.fighters)
		var path := PackedVector2Array()
		Predict.trajectory(them, CpuController.PATH_FRAMES, world.ai_world.stage_model, path)
		var approach := 1 << MoveBook.Approach.DASH if slot == Moveset.DASH_ATTACK else 1 << MoveBook.Approach.STAND
		var only := func(p: MoveProfile) -> bool: return p.slot == slot
		var options := MoveBook.of(attacker_data.moveset).moves_hitting(me, them, path, 40,
				world.ai_world.stage_model, approach, only)
		var predicted := not options.is_empty()
		var option: MoveBook.Option = options[0] if predicted else MoveBook.Option.new(
				MoveBook.of(attacker_data.moveset).get_profile(slot),
				MoveBook.Approach.DASH if slot == Moveset.DASH_ATTACK else MoveBook.Approach.STAND,
				attacker.facing if not MoveBook.of(attacker_data.moveset).get_profile(slot).turns_to_stick else (1 if gap > 0 else -1), 0, 0)
		cpu.force_plan(func(p: InputPlan) -> void: cpu.build_attack(p, option))
		await _frames(45)
		var actual := target.last_hit != null
		if actual == predicted:
			agree += 1
		if actual:
			hits += 1
		world.free()
	_check(agree >= trials * 0.95, "hit query agrees with HitResolver in %d/%d trials (%d hits)" % [agree, trials, hits])

## Wraps a controller: records every InputFrame and checks the poll changed
## nothing about the fighter (AI acts only through inputs).
class RecordingController extends FighterController:
	var inner: FighterController
	var frames: Array[PackedFloat32Array] = []
	var too_long := 0
	var tampered := 0

	func _init(p_inner: FighterController) -> void:
		inner = p_inner

	func poll(fighter: Fighter) -> InputFrame:
		var before := _fingerprint(fighter)
		var state := fighter.state
		var input := inner.poll(fighter)
		if fighter.state != state or _fingerprint(fighter) != before:
			tampered += 1
		if input.stick.length() > 1.0001 or input.cstick.length() > 1.0001:
			too_long += 1
		frames.append(PackedFloat32Array([input.stick.x, input.stick.y, input.cstick.x, input.cstick.y,
				float(input.attack), float(input.special), float(input.jump), float(input.shield), float(input.smash)]))
		return input

	static func _fingerprint(f: Fighter) -> PackedFloat32Array:
		return PackedFloat32Array([f.global_position.x, f.global_position.y, f.velocity_self.x, f.velocity_self.y,
				f.velocity_knockback.x, f.velocity_knockback.y, f.facing, f.percent, f.jumps_used, f.shield_hp,
				f.hitlag_frames, f.state.frame])


## Two CPU vs CPU runs with the same seeds produce the same inputs; sticks
## stay in range and the AI never touches fighter state.
func _test_cpu_determinism_and_inputs() -> void:
	var runs: Array[Array] = []
	for run in 2:
		var world := _world()
		var recorders: Array[RecordingController] = []
		for i in 2:
			var cpu := _add_cpu(world, CAT if i == 0 else BEAR, Vector3(-4.5 if i == 0 else 4.5, 0.0, 0.0), 9, CpuController.Mode.FIGHT, 1000 + i)
			var recorder := RecordingController.new(cpu)
			world.fighters[i].controller = recorder
			recorders.append(recorder)
		await _frames(1200)
		runs.append([recorders[0].frames, recorders[1].frames])
		if run == 0:
			_check(recorders[0].too_long + recorders[1].too_long == 0, "CPU sticks never exceed length 1")
			_check(recorders[0].tampered + recorders[1].tampered == 0, "CPUs change fighters only through inputs (%d)" % (recorders[0].tampered + recorders[1].tampered))
			var acted := false
			for frame: PackedFloat32Array in recorders[0].frames:
				acted = acted or frame[4] > 0.0 or frame[8] > 0.0
			_check(acted, "a level 9 CPU attacks within 20 seconds")
		world.free()
	var same: bool = runs[0][0] == runs[1][0] and runs[0][1] == runs[1][1]
	_check(same, "same seed, same CPU inputs for 1200 frames")


## Frames from the start of a scripted forward smash to the CPU's first
## defensive input, per trial (-1: never defended).
func _reaction_trials(level: int, trials: int) -> Array[int]:
	var results: Array[int] = []
	for trial in trials:
		var world := _world()
		var smash_at := 4
		var attacker := _add_fighter(world, BEAR, Vector3(-1.0, 0.0, 0.0), func(f: int) -> InputFrame:
			var input := _input()
			input.smash = f == smash_at
			return input)
		attacker.facing = 1
		var cpu := _add_cpu(world, CAT, Vector3(1.0, 0.0, 0.0), level, CpuController.Mode.FIGHT, 50 + trial)
		# Only defence is under test: no attacks of its own.
		cpu.params.follow_through = 0.0
		var reaction := -1
		for i in 45:
			await physics_frame
			if reaction < 0 and cpu.telemetry.defends > 0:
				reaction = i + 1 - smash_at
		results.append(reaction)
		world.free()
	return results


## The same scripted forward smash is defended later by level 3 than by level 9,
## and never sooner than the reaction time after it starts.
func _test_cpu_reaction() -> void:
	var low := await _reaction_trials(3, 12)
	var high := await _reaction_trials(9, 12)
	var difficulty := CpuDifficulty.load_default()
	var too_soon := 0
	for pair: Array in [[low, difficulty.sample(CpuDifficulty.skill_for_level(3)).reaction_frames],
			[high, difficulty.sample(CpuDifficulty.skill_for_level(9)).reaction_frames]]:
		for reaction: int in pair[0]:
			if reaction >= 0 and reaction < pair[1]:
				too_soon += 1
	var mean := func(values: Array[int]) -> float:
		var total := 0.0
		for value in values:
			total += value if value >= 0 else 60
		return total / values.size()
	_check(too_soon == 0, "no CPU defends sooner than its reaction time (%d early)" % too_soon)
	_check(mean.call(low) > mean.call(high), "level 3 defends later than level 9 (%.1f vs %.1f frames)" % [mean.call(low), mean.call(high)])
	var defended := 0
	for reaction in high:
		defended += 1 if reaction >= 0 else 0
	_check(defended >= high.size() * 0.6, "level 9 defends a slow forward smash most of the time (%d/%d)" % [defended, high.size()])


## Share of trials where a CPU at [param level] hits a Bear during the endlag
## of a forward smash it whiffed.
func _punish_rate(level: int, trials: int) -> float:
	var punished := 0
	var move := BEAR.moveset.forward_smash
	var endlag_start := MoveBook.of(BEAR.moveset).get_profile(Moveset.FORWARD_SMASH).active_end
	for trial in trials:
		var world := _world()
		var smash_at := 3
		# Far enough behind the Bear that the CPU can't reach it before the endlag.
		var bear := _add_fighter(world, BEAR, Vector3(-2.5, 0.0, 0.0), func(f: int) -> InputFrame:
			var input := _input()
			input.smash = f == smash_at
			return input)
		bear.facing = -1
		_add_cpu(world, CAT, Vector3(2.5, 0.0, 0.0), level, CpuController.Mode.FIGHT, 300 + trial)
		var hit_at := [-1]
		bear.hit_taken.connect(func(info: HitInfo) -> void:
			if not info.shielded and hit_at[0] < 0:
				hit_at[0] = (bear.controller as ScriptedController).frame)
		await _frames(move.total_frames + 8)
		var frame: int = hit_at[0] - smash_at + 1
		if hit_at[0] >= 0 and frame > endlag_start and frame <= move.total_frames + 2:
			punished += 1
		world.free()
	return float(punished) / trials


func _test_cpu_punish() -> void:
	var high := await _punish_rate(9, 12)
	var low := await _punish_rate(1, 12)
	_check(high >= 0.9, "level 9 punishes a whiffed forward smash (%.0f%%)" % (high * 100.0))
	_check(low <= 0.2, "level 1 rarely punishes it (%.0f%%)" % (low * 100.0))


## Each level plays 60 s against a stand dummy without self-destructing.
func _test_cpu_no_self_destructs() -> void:
	var total := 0
	var details: PackedStringArray = []
	for level in range(1, 10):
		var world := _world()
		var dummy := _add_cpu(world, BEAR, Vector3(3.0, 0.0, 0.0), 3, CpuController.Mode.STAND, level)
		var cpu := _add_cpu(world, CAT, Vector3(-3.0, 0.0, 0.0), level, CpuController.Mode.FIGHT, 700 + level)
		var fighter := world.fighters[1]
		# A self-destruct: a KO after standing on the stage (or a ledge) since the last hit.
		var safe := [true]
		fighter.hit_taken.connect(func(info: HitInfo) -> void:
			if not info.shielded:
				safe[0] = false)
		var sds := [0]
		fighter.knocked_out.connect(func(_f: Fighter) -> void:
			if safe[0]:
				sds[0] += 1)
		for i in 3600:
			await physics_frame
			if fighter.hitlag_frames == 0 and (fighter.grounded and not (fighter.state is HitstunState \
					or fighter.state is KnockdownState) or fighter.state is LedgeHangState or fighter.state is RespawnState):
				safe[0] = true
		total += sds[0]
		details.append("lv%d %d SD, dealt %.0f%%/%d KO" % [level, sds[0], world.fighters[0].percent, fighter.kos])
		world.free()
	_check(total == 0, "no self-destructs in 60 s per level (%s)" % ", ".join(details))
	print("vs stand dummy: ", ", ".join(details))


## From a grid of offstage starts the planner says are recoverable, level 9
## gets back at least 98% of the time and level 1 at least 80%.
func _test_cpu_recovery_grid() -> void:
	var starts: Array[Array] = []
	for data: FighterData in [CAT, BEAR]:
		for dx: float in [12.0, 30.0, 50.0]:
			for dy: float in [15.0, -10.0, -35.0]:
				for velocity: Vector2 in [Vector2(0.8, 0.5), Vector2(0.0, -0.5)]:
					starts.append([data, dx, dy, velocity])
	var probe := _world()
	var stage := probe.ai_world.stage_model
	var recoverable: Array[Array] = []
	for start in starts:
		var data: FighterData = start[0]
		var body := Predict.Body.new(data.stats, Vector2(stage.main_right + start[1], stage.main_top + start[2]), start[3])
		var plan_start := RecoveryPlanner.Start.new()
		plan_start.body = body
		plan_start.jumps_left = data.stats.jump_count - 1
		plan_start.special = data.moveset.up_special
		plan_start.special_rise = RecoveryPlanner.special_reach(plan_start.special, data.stats).y
		if not RecoveryPlanner.successful(plan_start, 8, stage).is_empty():
			recoverable.append(start)
	probe.free()
	_check(recoverable.size() >= starts.size() / 2, "most grid starts are recoverable (%d/%d)" % [recoverable.size(), starts.size()])
	for level: int in [9, 1]:
		var made := 0
		var failed: PackedStringArray = []
		for start in recoverable:
			var world := _world()
			var data: FighterData = start[0]
			var cpu := _add_cpu(world, data, Vector3.ZERO, level, CpuController.Mode.FIGHT, 900)
			var fighter := world.fighters[0]
			var origin := world.ai_world.stage_model
			fighter.global_position = Vector3(Units.to_meters(origin.main_right + start[1]), Units.to_meters(origin.main_top + start[2]), 0.0)
			fighter.velocity_self = start[3]
			fighter.grounded = false
			fighter.jumps_used = 1
			fighter.change_state(AirState.new(fighter))
			var back := false
			for i in 360:
				await physics_frame
				if fighter.state is LedgeHangState or fighter.grounded and not origin.is_offstage(Units.point_to_units(fighter.global_position)):
					back = true
					break
				if fighter.falls > 0:
					break
			if back:
				made += 1
			else:
				failed.append("%s %+.0f,%+.0f" % [data.display_name, start[1], start[2]])
			cpu.plan.clear()
			world.free()
		var rate := float(made) / maxi(recoverable.size(), 1)
		var needed := 0.98 if level == 9 else 0.8
		_check(rate >= needed, "level %d recovers from %.0f%% of recoverable starts (failed: %s)" % [level, rate * 100.0, ", ".join(failed)])


## Recovery plans play out in the game as the planner simulated them:
## fast-falling starts, double jump into up special, Bear's steered up special.
func _test_recovery_fidelity() -> void:
	# Character, feet, velocity, fast falling, jumps left, jump frame, special frame.
	var cases: Array[Array] = [
		[CAT, Vector2(86, -60), Vector2(0, -2.4), true, 1, 1, 2],
		[CAT, Vector2(86, -60), Vector2(0, -2.4), true, 1, 1, 9],
		[CAT, Vector2(86, -60), Vector2(0, -2.4), true, 0, -1, 1],
		[CAT, Vector2(95, -40), Vector2(0.5, -1.0), false, 1, 3, 15],
		[BEAR, Vector2(-100, -50), Vector2(0, -1.0), false, 1, 1, 12],
		[BEAR, Vector2(100, -40), Vector2(0, -2.8), true, 0, -1, 1],
	]
	for c in cases:
		var data: FighterData = c[0]
		var world := _world()
		var cpu := _add_cpu(world, data, Vector3.ZERO, 9, CpuController.Mode.STAND)
		var f := world.fighters[0]
		await _frames(1)
		f.change_state(AirState.new(f))
		f.global_position = Vector3(c[1].x, c[1].y, 0.0) / Units.PER_METER
		f.velocity_self = c[2]
		f.fast_falling = c[3]
		f.jumps_used = data.stats.jump_count - c[4]
		f.grounded = false
		var plan := RecoveryPlanner.Plan.new()
		plan.jump_at = c[5]
		plan.special_at = c[6]
		RecoveryPlanner.simulate(RecoveryPlanner.Start.of(f), plan, world.ai_world.stage_model, true)
		cpu.poll(f)
		cpu.force_plan(func(_p: InputPlan) -> void: pass)
		RecoverSituation.new()._follow(cpu, plan)
		cpu.plan.committed = true
		var worst := 0.0
		var ended := false
		for i in plan.path.size():
			await physics_frame
			if f.state is LedgeHangState or f.grounded:
				ended = true
				break
			worst = maxf(worst, Units.point_to_units(f.global_position).distance_to(plan.path[i]))
		var name := "%s from %s (jump %d, special %d)" % [data.display_name, c[1], c[5], c[6]]
		_check(plan.success and ended, "%s: the planned recovery works in the game" % name)
		_check(worst < 0.5, "%s: the game follows the planned path (off by %.2f)" % [name, worst])
		world.free()


## The same kill-percent hit: a level 9 CPU's DI survives it where a no-DI dummy dies.
func _di_survives(percent: float, level: int) -> bool:
	var world := _world()
	var attacker := _add_fighter(world, BEAR, Vector3(3.6, 0.0, 0.0), func(f: int) -> InputFrame:
		var input := _input()
		input.smash = f == 3
		return input)
	attacker.facing = 1
	var mode := CpuController.Mode.FIGHT if level > 0 else CpuController.Mode.STAND
	var cpu := _add_cpu(world, CAT, Vector3(5.0, 0.0, 0.0), maxi(level, 1), mode, 11)
	# Stand still until hit (the hit clears forced plans).
	cpu.force_plan(func(p: InputPlan) -> void: p.wait(200))
	var victim := world.fighters[1]
	victim.facing = -1
	await _frames(2)
	victim.percent = percent
	await _frames(240)
	var alive := victim.falls == 0
	var hit := victim.last_hit != null and not victim.last_hit.shielded
	world.free()
	return alive or not hit


func _test_cpu_di() -> void:
	var kill_percent := -1.0
	for percent in range(60, 200, 4):
		if not await _di_survives(percent, 0):
			kill_percent = percent
			break
	_check(kill_percent > 0.0, "a no-DI dummy dies to Bear's forward smash at %.0f%%" % kill_percent)
	if kill_percent > 0.0:
		_check(await _di_survives(kill_percent, 9), "a level 9 CPU's DI survives it at %.0f%%" % kill_percent)

#endregion
