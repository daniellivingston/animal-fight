class_name PlayerSlot
extends RefCounted
## Who controls one fighter in a match, and with which character.

enum Kind { HUMAN, CPU }

var kind := Kind.HUMAN
## Index into Match.roster.
var character := 0
## Input Map slot for humans (1 or 2; see PlayerActions). Assigned by
## [method Match.apply_controllers] in slot order.
var input_slot := 1
## CPU difficulty 1-9 (Smash default: 3), or 10 for the hidden frame-perfect level.
var cpu_level := CpuController.DEFAULT_LEVEL
## CPU behaviour mode (Smash's CPU modes); FIGHT is normal play.
var cpu_mode := CpuController.Mode.FIGHT
## DI of the training modes (STAND, SHIELD, JUMP).
var dummy_di := AiDi.Mode.NONE


func _init(p_kind: Kind = Kind.HUMAN, p_character: int = 0) -> void:
	kind = p_kind
	character = p_character


func is_cpu() -> bool:
	return kind == Kind.CPU


## "CPU 3", "Dummy" or "" for humans, for the HUD.
func label() -> String:
	if kind == Kind.HUMAN:
		return ""
	if cpu_mode != CpuController.Mode.FIGHT:
		return "Dummy"
	return "CPU %d" % cpu_level


## Level colours from indigo (1) to red (9), as in Smash 4 and Ultimate.
static func level_color(level: int) -> Color:
	var t := clampf((level - 1) / 8.0, 0.0, 1.0)
	return Color(0.36, 0.3, 0.95).lerp(Color(0.95, 0.15, 0.2), t)


func color() -> Color:
	if kind == Kind.HUMAN or cpu_mode != CpuController.Mode.FIGHT:
		return Color(0.75, 0.78, 0.85)
	return level_color(cpu_level)


func save(config: ConfigFile, section: String) -> void:
	config.set_value(section, "kind", kind)
	config.set_value(section, "cpu_level", cpu_level)
	config.set_value(section, "cpu_mode", cpu_mode)
	config.set_value(section, "dummy_di", dummy_di)


func load_from(config: ConfigFile, section: String) -> void:
	if not config.has_section(section):
		return
	kind = clampi(config.get_value(section, "kind", kind), 0, Kind.size() - 1) as Kind
	cpu_level = clampi(config.get_value(section, "cpu_level", cpu_level), 1, CpuController.DEBUG_LEVEL)
	cpu_mode = clampi(config.get_value(section, "cpu_mode", cpu_mode), 0, CpuController.Mode.size() - 1) as CpuController.Mode
	dummy_di = clampi(config.get_value(section, "dummy_di", dummy_di), 0, AiDi.Mode.size() - 1) as AiDi.Mode
