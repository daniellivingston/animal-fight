class_name Match
extends Node
## A training match: the stage, two fighters, the camera and the UI.
##
## The match owns the simulation loop. Each physics tick (one Smash frame) it
## advances every fighter, resolves hits between them, separates overlapping
## fighters, checks blast zones, records what CPUs will see ([AiWorld]) and
## then updates visuals. Fighters never run their own physics callbacks, so
## the order is fixed and frame-exact.

## Push between overlapping grounded fighters, units/frame.
const _SEPARATION_SPEED := 0.4
## Where the slot settings (human or CPU, level, mode) are kept between runs.
const SETTINGS_PATH := "user://settings.cfg"

@export var stage_scene: PackedScene
@export var fighter_scene: PackedScene
@export var roster: Array[FighterData] = []

## Who plays each fighter, in player order.
var slots: Array[PlayerSlot] = []
## Seeds every CPU's random choices (with its slot), so a match can be
## reproduced. New at each start and reset; shown in the training overlay.
var match_seed := 0
var stage: Stage
var fighters: Array[Fighter] = []
## What CPUs see: snapshots of every fighter, captured at the end of each frame.
var ai_world: AiWorld

@onready var _fighters_root: Node3D = %Fighters
@onready var _camera: FightCamera = %FightCamera
@onready var _hud: Hud = %HUD
@onready var _training_info: TrainingInfo = %TrainingInfo
@onready var _pause_menu: PauseMenu = %PauseMenu


func _ready() -> void:
	stage = stage_scene.instantiate() as Stage
	add_child(stage)
	move_child(stage, 0)
	ai_world = AiWorld.new(stage, fighters)
	var ai_debug := AiDebugDraw.new()
	add_child(ai_debug)
	ai_debug.setup(self)
	_default_slots()
	load_settings()
	_pause_menu.setup(self)
	start()


## P1 is a human. P2 is the stand dummy, or a level 3 CPU on touch devices,
## where there is only one human.
func _default_slots() -> void:
	slots = [PlayerSlot.new(PlayerSlot.Kind.HUMAN, 0), PlayerSlot.new(PlayerSlot.Kind.CPU, 1)]
	if GameInput.device != GameInput.Device.TOUCH:
		slots[1].cpu_mode = CpuController.Mode.STAND


## (Re)creates every fighter from [member slots] at their spawn points.
func start() -> void:
	for fighter in fighters:
		fighter.queue_free()
	fighters.clear()
	for i in slots.size():
		var fighter := fighter_scene.instantiate() as Fighter
		fighter.data = roster[slots[i].character]
		fighter.player_slot = i + 1
		fighter.stage = stage
		fighter.name = "P%d" % (i + 1)
		_fighters_root.add_child(fighter)
		fighters.append(fighter)
	_hud.setup(fighters, slots)
	_training_info.setup(self)
	reset()
	_camera.setup(stage, fighters)


## Puts every fighter back at its spawn point with 0% and no KOs, and starts
## the CPUs over with a new seed.
func reset() -> void:
	for i in fighters.size():
		var fighter := fighters[i]
		fighter.spawn(stage.spawn_point(i))
		fighter.facing = 1 if fighter.global_position.x <= 0.0 else -1
		fighter.kos = 0
		fighter.falls = 0
		fighter.sync_visuals()
	match_seed = randi()
	apply_controllers()


## Gives each fighter the controller its slot asks for. Humans take the Input
## Map slots in player order; CPUs get fresh controllers seeded from
## [member match_seed] and their slot.
func apply_controllers() -> void:
	ai_world.clear()
	var next_input := 1
	for i in mini(slots.size(), fighters.size()):
		var slot := slots[i]
		if slot.kind == PlayerSlot.Kind.HUMAN and next_input <= InputActions.MAX_LOCAL_PLAYERS:
			slot.input_slot = next_input
			next_input += 1
			fighters[i].controller = PlayerController.new(slot.input_slot)
		else:
			var cpu := CpuController.new(slot.cpu_level, slot.cpu_mode)
			cpu.dummy_di = slot.dummy_di
			cpu.setup(ai_world, CpuController.seed_for(match_seed, i), fighters[i].data.cpu_profile)
			fighters[i].controller = cpu
	_hud.refresh_labels()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	for i in slots.size():
		slots[i].save(config, "p%d" % (i + 1))
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for i in slots.size():
		slots[i].load_from(config, "p%d" % (i + 1))


func _physics_process(_delta: float) -> void:
	for fighter in fighters:
		fighter.tick()
	var damage_ratio := SmashFormulas.ONE_ON_ONE_DAMAGE if fighters.size() == 2 else 1.0
	HitResolver.resolve(fighters, damage_ratio)
	_separate_fighters()
	for fighter in fighters:
		if not fighter.state is KOState and fighter.is_outside_blast_zone(stage.blast_zone):
			_burst(fighter)
			fighter.knock_out()
		fighter.sync_visuals()
	ai_world.capture()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE):
		_pause_menu.open()
	elif event.is_action_pressed(InputActions.TOGGLE_HITBOXES):
		DebugSettings.show_hitboxes = not DebugSettings.show_hitboxes
	elif event.is_action_pressed(InputActions.TOGGLE_TRAINING_INFO):
		DebugSettings.show_training_info = not DebugSettings.show_training_info
	elif event.is_action_pressed(InputActions.TOGGLE_AI_DEBUG):
		DebugSettings.show_ai_debug = not DebugSettings.show_ai_debug
		if DebugSettings.show_ai_debug:
			DebugSettings.show_training_info = true
	elif event.is_action_pressed(InputActions.RESET_MATCH):
		reset()
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Phones and browser tabs going to the background pause the game.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and (OS.has_feature("mobile") or OS.has_feature("web")):
		if is_node_ready():
			_pause_menu.open()


## Grounded fighters standing in each other slowly push apart, as in Smash.
func _separate_fighters() -> void:
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			var a := fighters[i]
			var b := fighters[j]
			if not a.grounded or not b.grounded or not a.visible or not b.visible:
				continue
			var dx := Units.to_units(b.global_position.x - a.global_position.x)
			var dy := Units.to_units(absf(b.global_position.y - a.global_position.y))
			var overlap := a.stats.radius + b.stats.radius - absf(dx)
			if overlap <= 0.0 or dy > a.stats.height * 0.5:
				continue
			var direction := signf(dx) if dx != 0.0 else 1.0
			a.velocity_push.x -= direction * _SEPARATION_SPEED
			b.velocity_push.x += direction * _SEPARATION_SPEED


func _burst(fighter: Fighter) -> void:
	var bounds := stage.camera_bounds
	var p := fighter.global_position
	var at := Vector3(clampf(p.x, bounds.position.x, bounds.end.x),
			clampf(p.y, bounds.position.y, bounds.end.y), 0.0)
	KOBurst.spawn(self, at, fighter.data.color)
