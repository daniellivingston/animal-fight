class_name DamageMeter
extends PanelContainer
## A fighter's damage percent, Smash style: the number reddens as it climbs and
## shakes when hit. Also shows KOs and falls.

## Percent at which the number is fully red.
const RED_PERCENT := 150.0
const SHAKE_FRAMES := 12

var fighter: Fighter

var _name_label := Label.new()
var _percent_label := Label.new()
var _score_label := Label.new()
var _shake := 0


func setup(p_fighter: Fighter) -> void:
	fighter = p_fighter
	fighter.hit_taken.connect(_on_hit_taken)
	custom_minimum_size = Vector2(190.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.55)
	style.border_color = fighter.data.color
	style.border_width_bottom = 4
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8.0)
	add_theme_stylebox_override(&"panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", -4)
	add_child(column)
	_name_label.text = "P%d  %s" % [fighter.player_slot, fighter.data.display_name.to_upper()]
	_name_label.add_theme_color_override(&"font_color", fighter.data.color.lightened(0.3))
	_name_label.add_theme_font_size_override(&"font_size", 18)
	_percent_label.add_theme_font_size_override(&"font_size", 44)
	_percent_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_percent_label.add_theme_constant_override(&"outline_size", 8)
	_score_label.add_theme_font_size_override(&"font_size", 16)
	for label: Label in [_name_label, _percent_label, _score_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)


func _process(_delta: float) -> void:
	if not is_instance_valid(fighter):
		return
	var knocked_out := fighter.state is KOState
	_percent_label.text = "—" if knocked_out else "%d%%" % floori(fighter.percent)
	var t := clampf(fighter.percent / RED_PERCENT, 0.0, 1.0)
	_percent_label.add_theme_color_override(&"font_color",
			Color.WHITE.lerp(Color(1.0, 0.75, 0.2), minf(t * 2.0, 1.0)).lerp(Color(0.8, 0.05, 0.05), maxf(t * 2.0 - 1.0, 0.0)))
	_score_label.text = "KOs %d · Falls %d" % [fighter.kos, fighter.falls]
	if _shake > 0:
		_shake -= 1
		_percent_label.position.x = randf_range(-4.0, 4.0) * _shake / SHAKE_FRAMES
	else:
		_percent_label.position.x = 0.0


func _on_hit_taken(info: HitInfo) -> void:
	if not info.shielded:
		_shake = SHAKE_FRAMES
