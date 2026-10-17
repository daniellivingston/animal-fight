extends CanvasLayer
## On-screen controls for touch devices: a floating stick on the left and the
## four fighting buttons on the right, all feeding player 1's actions. Shown
## while touch is the active device and the game isn't paused. Also asks phone
## players to turn the screen sideways.

@onready var _root: Control = %SafeArea
@onready var _rotate_hint: Control = %RotateHint


func _ready() -> void:
	GameInput.device_changed.connect(_refresh.unbind(1))
	get_viewport().size_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	var show := GameInput.device == GameInput.Device.TOUCH and not get_tree().paused
	if _root.visible != show:
		_refresh()


func _refresh() -> void:
	var touch := GameInput.device == GameInput.Device.TOUCH
	_root.visible = touch and not get_tree().paused
	var size := get_viewport().get_visible_rect().size
	_rotate_hint.visible = touch and size.y > size.x
