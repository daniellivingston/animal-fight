extends SceneTree
## CPU ladder harness and benchmark. Slow; run by hand, not part of run_tests.gd.
##
## Ladder: plays first-to-N-KO matches between CPU levels (and characters) and
## prints the win-rate matrix plus telemetry per level. Each level should beat
## the one below it at least 60% of the time.
##   Godot --headless --path . --fixed-fps 60 --script res://tests/ai_ladder.gd -- --matches=20
## Options: --levels=1,2,...,9  --pairs=adjacent|all|vs:<level>  --characters=cat,bear
##   --stocks=3  --minutes=6  --seed=1  --quiet  --log-sd (print the frames before
##   each self-destruct)  --log-plans (print each recovery plan)  --only=<match>
##   (replay one match of each pair)
## Several processes can split the work, e.g. one per --levels=4,5.
##
## Benchmark: CPU level 9 vs level 9, timing every CpuController.poll().
##   Godot --headless --path . --fixed-fps 60 --script res://tests/ai_ladder.gd -- --bench --frames=10000

const STAGE := preload("res://stages/meadow/meadow.tscn")
const FIGHTER := preload("res://fighters/fighter.tscn")
const ROSTER_DIR := "res://fighters/roster/"


## Times every poll of the wrapped controller.
class TimedController extends FighterController:
	var inner: FighterController
	var samples := PackedInt32Array()

	func _init(p_inner: FighterController) -> void:
		inner = p_inner

	func poll(fighter: Fighter) -> InputFrame:
		var start := Time.get_ticks_usec()
		var input := inner.poll(fighter)
		samples.append(Time.get_ticks_usec() - start)
		return input


## The match loop (as in Match, without visuals or UI).
class LadderWorld extends Node3D:
	var stage: Stage
	var fighters: Array[Fighter] = []
	var ai_world: AiWorld
	var frame := 0

	func step() -> void:
		frame += 1
		for fighter in fighters:
			fighter.tick()
		HitResolver.resolve(fighters, SmashFormulas.ONE_ON_ONE_DAMAGE)
		for fighter in fighters:
			if not fighter.state is KOState and fighter.is_outside_blast_zone(stage.blast_zone):
				fighter.knock_out()
		ai_world.capture()


## Per-level results.
class LevelStats:
	var wins := 0
	var games := 0
	var self_destructs := 0
	var falls := 0
	var frames := 0
	var telemetry := CpuTelemetry.new()


var _options := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_options = _parse(OS.get_cmdline_user_args())
	if _options.has("bench"):
		await _bench()
	else:
		await _ladder()
	quit()


func _parse(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var pair := arg.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else "true"
	return options


func _option(name: String, fallback: String) -> String:
	return String(_options.get(name, fallback))


func _roster(names: PackedStringArray) -> Array[FighterData]:
	var result: Array[FighterData] = []
	for name in names:
		var path := ROSTER_DIR + "%s/%s.tres" % [name, name]
		if ResourceLoader.exists(path):
			result.append(load(path) as FighterData)
		else:
			push_error("No roster character '%s'" % name)
	return result


func _make_world() -> LadderWorld:
	var world := LadderWorld.new()
	# Physics processing stays off: the harness steps worlds itself, one
	# simulation frame per physics frame.
	root.add_child(world)
	world.stage = STAGE.instantiate() as Stage
	world.add_child(world.stage)
	world.ai_world = AiWorld.new(world.stage, world.fighters)
	return world


func _add_cpu(world: LadderWorld, data: FighterData, index: int, level: int, seed: int) -> CpuController:
	var fighter := FIGHTER.instantiate() as Fighter
	fighter.data = data
	fighter.player_slot = index + 1
	fighter.stage = world.stage
	world.add_child(fighter)
	fighter.spawn(world.stage.spawn_point(index))
	fighter.facing = 1 if index == 0 else -1
	var cpu := CpuController.new(level)
	cpu.setup(world.ai_world, CpuController.seed_for(seed, index), data.cpu_profile)
	fighter.controller = cpu
	world.fighters.append(fighter)
	return cpu


## Plays one match; returns the winner's index (or -1 for a draw) and fills [param stats].
func _play(levels: Array[int], characters: Array[FighterData], seed: int, stats: Array[LevelStats]) -> int:
	var world := _make_world()
	var cpus: Array[CpuController] = []
	for i in 2:
		cpus.append(_add_cpu(world, characters[i], i, levels[i], seed))
	var stocks := int(_option("stocks", "3"))
	var limit := int(float(_option("minutes", "6")) * 60.0 * 60.0)
	# A KO is a self-destruct when the fighter stood on the stage or held a
	# ledge after the last hit it took: it went offstage on its own.
	var safe_since_hit := [true, true]
	var self_destructs := [0, 0]
	var log_sd := _options.has("log-sd")
	CpuController.debug_log = _options.has("log-plans")
	var history: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
	for i in 2:
		var index := i
		var fighter := world.fighters[i]
		fighter.hit_taken.connect(func(info: HitInfo) -> void:
			if not info.shielded:
				safe_since_hit[index] = false)
		fighter.knocked_out.connect(func(_f: Fighter) -> void:
			if safe_since_hit[index]:
				self_destructs[index] += 1
				if log_sd:
					print("SELF-DESTRUCT lv%d %s (seed %d, frame %d):\n%s" % [levels[index], characters[index].display_name,
							seed, world.frame, "\n".join(history[index].slice(-int(_option("log-frames", "150"))))]))
	while world.frame < limit and world.fighters[0].falls < stocks and world.fighters[1].falls < stocks:
		await physics_frame
		world.step()
		for i in 2:
			var f := world.fighters[i]
			if f.hitlag_frames == 0 and (f.grounded and not (f.state is HitstunState or f.state is KnockdownState) \
					or f.state is LedgeHangState or f.state is RespawnState):
				safe_since_hit[i] = true
		if log_sd:
			for i in 2:
				var f := world.fighters[i]
				var cpu := cpus[i]
				history[i].append("%d %s f%d (%.0f,%.0f) face%d v(%.2f,%.2f) j%d dodge%s | %s %s [%s] %s" % [world.frame,
						f.state.state_name(), f.state.frame, Units.to_units(f.global_position.x),
						Units.to_units(f.global_position.y), f.facing, f.velocity_self.x, f.velocity_self.y, f.jumps_used,
						"x" if f.air_dodge_used else "-", cpu.situation.situation_name() if cpu.situation else &"-",
						cpu.tactic, cpu.plan.label, cpu.plan.describe()])
				if history[i].size() > 400:
					history[i] = history[i].slice(-300)
	var a := world.fighters[0]
	var b := world.fighters[1]
	var winner := -1
	if a.falls != b.falls:
		winner = 0 if a.falls < b.falls else 1
	elif absf(a.percent - b.percent) > 0.5:
		winner = 0 if a.percent < b.percent else 1
	for i in 2:
		var s := stats[i]
		s.games += 1
		s.wins += 1 if winner == i else 0
		s.self_destructs += self_destructs[i]
		s.falls += world.fighters[i].falls
		s.frames += world.frame
		s.telemetry.merge(cpus[i].telemetry)
	world.free()
	return winner


func _ladder() -> void:
	var levels: Array[int] = []
	for value in _option("levels", "1,2,3,4,5,6,7,8,9").split(","):
		levels.append(int(value))
	var characters := _roster(_option("characters", "cat,bear").split(","))
	var matches := int(_option("matches", "10"))
	var base_seed := int(_option("seed", "1"))
	var pairs: Array[Vector2i] = []
	var mode := _option("pairs", "adjacent")
	for i in levels.size():
		for j in range(i + 1, levels.size()):
			if mode == "all" or (mode == "adjacent" and j == i + 1):
				pairs.append(Vector2i(levels[i], levels[j]))
			elif mode.begins_with("vs:") and (levels[i] == int(mode.substr(3)) or levels[j] == int(mode.substr(3))):
				pairs.append(Vector2i(levels[i], levels[j]))
	var per_level := {}
	var matrix := {}
	for level in levels:
		per_level[level] = LevelStats.new()
	var started := Time.get_ticks_msec()
	for pair in pairs:
		var wins_high := 0
		var decided := 0
		for m in matches:
			if _options.has("only") and m != int(_option("only", "0")):
				continue
			# Alternate characters and sides so neither has an edge.
			var high_first := m % 2 == 0
			var order: Array[int] = [pair.x, pair.y]
			if high_first:
				order = [pair.y, pair.x]
			var chars: Array[FighterData] = [characters[(m / 2) % characters.size()],
					characters[(m / 2 + 1) % characters.size()]]
			var stats: Array[LevelStats] = [LevelStats.new(), LevelStats.new()]
			var winner := await _play(order, chars, base_seed * 1000 + m * 7 + pair.x * 101 + pair.y, stats)
			for i in 2:
				var target: LevelStats = per_level[order[i]]
				target.wins += stats[i].wins
				target.games += stats[i].games
				target.self_destructs += stats[i].self_destructs
				target.falls += stats[i].falls
				target.frames += stats[i].frames
				target.telemetry.merge(stats[i].telemetry)
			if winner >= 0:
				decided += 1
				if order[winner] == pair.y:
					wins_high += 1
			if not _options.has("quiet"):
				print("  lv%d (%s) vs lv%d (%s): %s" % [order[0], chars[0].display_name, order[1], chars[1].display_name,
						"draw" if winner < 0 else "lv%d wins" % order[winner]])
		matrix[pair] = [wins_high, matches]
		print("lv%d beats lv%d in %d/%d (%.0f%%)" % [pair.y, pair.x, wins_high, matches, 100.0 * wins_high / maxi(matches, 1)])
	print("\nwin rate of the higher level, per pair:")
	for pair in pairs:
		var result: Array = matrix[pair]
		print("  %d > %d : %3.0f%%  (%d/%d)" % [pair.y, pair.x, 100.0 * result[0] / maxi(result[1], 1), result[0], result[1]])
	print("\nper level: win%, self-destructs, falls/game, avg reaction, defends, shields, punishes, recoveries, edgeguards, techs, match length")
	for level in levels:
		var s: LevelStats = per_level[level]
		if s.games == 0:
			continue
		var t := s.telemetry
		print("  lv%d: %3.0f%%  SD %d  falls %.1f  react %.1f f  def %d  shield %d  punish %d  recover %d  edgeguard %d  tech %d  %.0f s" % [
				level, 100.0 * s.wins / s.games, s.self_destructs, float(s.falls) / s.games, t.average_reaction(),
				t.defends, t.shields, t.punish_attempts, t.recoveries, t.edgeguards, t.techs, s.frames / 60.0 / s.games])
		var moves: PackedStringArray = []
		for slot in t.moves:
			moves.append("%s %d" % [slot, t.moves[slot]])
		print("        moves: ", ", ".join(moves))
	print("\n%d matches in %.0f s" % [pairs.size() * matches, (Time.get_ticks_msec() - started) / 1000.0])


func _bench() -> void:
	var frames := int(_option("frames", "10000"))
	var level := int(_option("level", "9"))
	var characters := _roster(_option("characters", "cat,bear").split(","))
	var world := _make_world()
	var timers: Array[TimedController] = []
	for i in 2:
		var cpu := _add_cpu(world, characters[i % characters.size()], i, level, 42)
		var timed := TimedController.new(cpu)
		world.fighters[i].controller = timed
		timers.append(timed)
	var started := Time.get_ticks_usec()
	for i in frames:
		await physics_frame
		world.step()
	var total := Time.get_ticks_usec() - started
	var samples := PackedInt32Array()
	for timer in timers:
		samples.append_array(timer.samples)
	samples.sort()
	var sum := 0
	for sample in samples:
		sum += sample
	var count := samples.size()
	print("CPU level %d vs %d, %d frames (%s)" % [level, level, frames, OS.get_name()])
	print("poll(): mean %.1f us, median %d us, p99 %d us, max %d us" % [float(sum) / count, samples[count / 2],
			samples[mini(count - 1, count * 99 / 100)], samples[count - 1]])
	print("whole frame (2 fighters, physics included): %.1f us" % (float(total) / frames))
	print("falls %d / %d" % [world.fighters[0].falls, world.fighters[1].falls])
	world.free()
