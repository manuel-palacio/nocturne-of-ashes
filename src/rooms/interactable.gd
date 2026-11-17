class_name Interactable
extends StaticBody3D
## Something in a room that is clicked but is not a combatant. A unit ordered to it walks within
## `reach` and uses it. It needs a collision shape as a child to be clicked, sits on the "interact"
## layer (4) only, whatever a scene sets, and is not in the `&"units"` group, so brains and the Fury
## never see it; it is in the `&"interactables"` group instead. It can show a pale ring on the floor,
## the mark that it can be used, at `use_mark_position()`.

signal used(by: Unit)

## The ring that marks it as usable: outer radius and width in metres, and colour.
const USE_MARK_RADIUS: float = 0.5
const USE_MARK_WIDTH: float = 0.03
const USE_MARK_COLOUR: Color = Color(0.9, 0.88, 0.8)

## What it is, shown to the player; translatable.
@export var label: String = ""
## A unit uses it from this flat distance or nearer, in metres.
@export var reach: float = 2.0
## Whether only the party's leader uses it: a click on it sends the leader, whoever is selected.
@export var leader_only: bool = false

var _use_mark: FloorRing


# Set on entering the tree through `_notification`, which runs for every class in the hierarchy,
# so no subclass can lose it by skipping `super()`. Scripts never receive POSTINITIALIZE.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		collision_layer = 0b1000
		collision_mask = 0
		add_to_group(&"interactables")


## Whether `unit` may use it; always true here, narrowed by subclasses.
func can_be_used_by(_unit: Unit) -> bool:
	return true


## Emits `used` if `by` may use it; subclasses add what happens. Returns whether it was used.
func use(by: Unit) -> bool:
	if not can_be_used_by(by):
		return false
	used.emit(by)
	return true


## Shows or hides the ring that marks it as usable.
func set_use_mark(on: bool) -> void:
	if on and _use_mark == null:
		_use_mark = FloorRing.new(USE_MARK_RADIUS, USE_MARK_WIDTH, USE_MARK_COLOUR)
		_use_mark.name = &"UseMark"
		add_child(_use_mark)
		_use_mark.position = use_mark_position() + Vector3.UP * FloorRing.LIFT
	if _use_mark != null:
		_use_mark.visible = on


func has_use_mark() -> bool:
	return _use_mark != null and _use_mark.visible


## Whether its use ring may show for `unit`: it may use it now. Subclasses narrow it further.
func offers_use_to(unit: Unit) -> bool:
	return can_be_used_by(unit)


## Where its use ring lies, on the floor in its own frame: under it, unless a subclass says otherwise.
func use_mark_position() -> Vector3:
	return Vector3.ZERO
