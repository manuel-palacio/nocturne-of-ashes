class_name Hud
extends CanvasLayer
## Shows the player unit's name and health, and the prompt to restart after falling.

var _unit: Unit

@onready var _name_label: Label = %NameLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _fallen_label: Label = %FallenLabel


func _ready() -> void:
	hide_fallen()


## Follows `unit`'s health from now on, dropping any unit bound before.
func bind(unit: Unit) -> void:
	if is_instance_valid(_unit) and _unit.stats.health_changed.is_connected(_on_health_changed):
		_unit.stats.health_changed.disconnect(_on_health_changed)
	_unit = unit
	_name_label.text = unit.display_name
	unit.stats.health_changed.connect(_on_health_changed)
	_on_health_changed(unit.stats.health, unit.stats.max_health)


func show_fallen() -> void:
	_fallen_label.visible = true


func hide_fallen() -> void:
	_fallen_label.visible = false


func is_fallen_shown() -> bool:
	return _fallen_label.visible


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
