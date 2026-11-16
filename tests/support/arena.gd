class_name Arena
extends RefCounted
## Test helper: the flat fixture room with units placed in it.

const ROOM: PackedScene = preload("res://tests/fixtures/flat_room.tscn")
const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const ZAHRA: PackedScene = preload("res://scenes/units/zahra.tscn")
const GONZALO: PackedScene = preload("res://scenes/units/gonzalo.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")
const SERGEANT: PackedScene = preload("res://scenes/units/crusader_sergeant.tscn")

var room: Node3D


## An interactable whose `allow` decides who may use it.
class Picky extends Interactable:
	var _allow: Callable

	func _init(allow: Callable) -> void:
		super()
		_allow = allow

	func can_be_used_by(unit: Unit) -> bool:
		return _allow.call(unit)


func _init(test: GutTest) -> void:
	room = test.add_child_autofree(ROOM.instantiate())


## Adds a unit at `at`. Its Brain, if it has one, is removed unless `with_brain` is true, when it is enabled.
func spawn(scene: PackedScene, at: Vector3, with_brain: bool = false) -> Unit:
	var unit: Unit = scene.instantiate()
	var brain: Node = unit.get_node_or_null(^"Brain")
	if brain != null and not with_brain:
		unit.remove_child(brain)
		brain.free()
	room.add_child(unit)
	unit.global_position = at
	if with_brain and brain is CombatBrain:
		(brain as CombatBrain).enabled = true
	return unit


## Adds an `Interactable` with a 0.7 m × 1.8 m capsule collider, standing on the floor at `at`. When
## `allow` is valid, it decides who may use it.
func add_interactable(at: Vector3, allow: Callable = Callable()) -> Interactable:
	var thing: Interactable = Picky.new(allow) if allow.is_valid() else Interactable.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	thing.add_child(shape)
	room.add_child(thing)
	thing.global_position = at
	return thing


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
