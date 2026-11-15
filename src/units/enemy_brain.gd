class_name EnemyBrain
extends Node
## Makes its `Unit` attack the nearest living hostile unit that comes within `aggro_radius`.

@export var aggro_radius: float = 8.0
@export var think_interval: float = 0.25

var _since_thought: float = 0.0

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	_since_thought += delta
	if _since_thought < think_interval:
		return
	_since_thought = 0.0
	if not _unit.is_alive() or _unit.attack_target() != null:
		return
	var nearest: Unit = _nearest_hostile()
	if nearest != null:
		_unit.order_attack(nearest)


func _nearest_hostile() -> Unit:
	var nearest: Unit = null
	var best: float = aggro_radius
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == _unit or not other.is_alive() or not _unit.is_hostile_to(other):
			continue
		var distance: float = _unit.global_position.distance_to(other.global_position)
		if distance <= best:
			best = distance
			nearest = other
	return nearest
