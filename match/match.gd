class_name Match
extends Node
## A training match: the stage, two fighters, the camera and the UI.
##
## The match owns the simulation loop. Each physics tick (one Smash frame) it
## advances every fighter, resolves hits between them, separates overlapping
## fighters, checks blast zones and then updates visuals. Fighters never run
## their own physics callbacks, so the order is fixed and frame-exact.

## Push between overlapping grounded fighters, units/frame.
const _SEPARATION_SPEED := 0.4

@export var stage_scene: PackedScene
@export var fighter_scene: PackedScene
@export var roster: Array[FighterData] = []

## Roster index for each player slot.
var selections: Array[int] = [0, 1]
## Whether player 2 is a local player (keyboard arrows / gamepad 2) or the dummy.
var player_two_human := false
var dummy := DummyController.new()
var stage: Stage
var fighters: Array[Fighter] = []

@onready var _fighters_root: Node3D = %Fighters
@onready var _camera: FightCamera = %FightCamera
@onready var _hud: Hud = %HUD
@onready var _training_info: TrainingInfo = %TrainingInfo
@onready var _pause_menu: PauseMenu = %PauseMenu


func _ready() -> void:
	stage = stage_scene.instantiate() as Stage
	add_child(stage)
	move_child(stage, 0)
	_pause_menu.setup(self)
	start()


## (Re)creates both fighters from [member selections] at their spawn points.
func start() -> void:
	for fighter in fighters:
		fighter.queue_free()
	fighters.clear()
	for i in selections.size():
		var fighter := fighter_scene.instantiate() as Fighter
		fighter.data = roster[selections[i]]
		fighter.player_slot = i + 1
		fighter.stage = stage
		fighter.name = "P%d" % (i + 1)
		_fighters_root.add_child(fighter)
		fighters.append(fighter)
	apply_controllers()
	reset()
	_camera.setup(stage, fighters)
	_hud.setup(fighters)
	_training_info.setup(fighters)


## Puts both fighters back at their spawn points with 0% and no KOs.
func reset() -> void:
	for i in fighters.size():
		var fighter := fighters[i]
		fighter.spawn(stage.spawn_point(i))
		fighter.facing = 1 if fighter.global_position.x <= 0.0 else -1
		fighter.kos = 0
		fighter.falls = 0
		fighter.sync_visuals()


func apply_controllers() -> void:
	if fighters.is_empty():
		return
	fighters[0].controller = PlayerController.new(1)
	if fighters.size() > 1:
		fighters[1].controller = PlayerController.new(2) if player_two_human else dummy


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PAUSE):
		_pause_menu.open()
	elif event.is_action_pressed(InputActions.TOGGLE_HITBOXES):
		DebugSettings.show_hitboxes = not DebugSettings.show_hitboxes
	elif event.is_action_pressed(InputActions.TOGGLE_TRAINING_INFO):
		DebugSettings.show_training_info = not DebugSettings.show_training_info
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
