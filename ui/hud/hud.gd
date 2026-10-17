class_name Hud
extends CanvasLayer
## Damage meters for every fighter, across the top of the screen (the bottom
## corners belong to the touch controls).

@onready var _meters: HBoxContainer = %Meters


func setup(fighters: Array[Fighter]) -> void:
	for child in _meters.get_children():
		child.queue_free()
	for fighter in fighters:
		var meter := DamageMeter.new()
		_meters.add_child(meter)
		meter.setup(fighter)
