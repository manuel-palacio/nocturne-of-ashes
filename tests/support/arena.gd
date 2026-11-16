class_name Arena
extends RefCounted
## Test helper: the flat fixture room with units placed in it.

const ROOM: PackedScene = preload("res://tests/fixtures/flat_room.tscn")
const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")

var room: Node3D


func _init(test: GutTest) -> void:
	room = test.add_child_autofree(ROOM.instantiate())


## Adds a unit at `at`. Its Brain, if it has one, is removed unless `with_brain` is true.
func spawn(scene: PackedScene, at: Vector3, with_brain: bool = false) -> Unit:
	var unit: Unit = scene.instantiate()
	var brain: Node = unit.get_node_or_null(^"Brain")
	if brain != null and not with_brain:
		unit.remove_child(brain)
		brain.free()
	room.add_child(unit)
	unit.global_position = at
	return unit


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
