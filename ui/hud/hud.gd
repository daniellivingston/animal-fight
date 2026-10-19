class_name Hud
extends CanvasLayer
## Damage meters for every fighter, across the top of the screen (the bottom
## corners belong to the touch controls). CPU slots show "CPU" and their level.

var _slots: Array[PlayerSlot] = []
var _meter_list: Array[DamageMeter] = []

@onready var _meters: HBoxContainer = %Meters


func setup(fighters: Array[Fighter], slots: Array[PlayerSlot]) -> void:
	_slots = slots
	_meter_list.clear()
	for child in _meters.get_children():
		child.queue_free()
	for fighter in fighters:
		var meter := DamageMeter.new()
		_meters.add_child(meter)
		meter.setup(fighter)
		_meter_list.append(meter)
	refresh_labels()


## Updates the CPU tags after slots change.
func refresh_labels() -> void:
	for i in mini(_meter_list.size(), _slots.size()):
		_meter_list[i].set_tag(_slots[i].label(), _slots[i].color().lightened(0.35))
