class_name Separation
extends Node
## Keeps its `Unit` from standing inside another: each physics frame `push()` gives a small flat velocity
## away from every other living unit closer than `radius`, which the unit adds to its own for that one
## move. The push grows with the overlap up to `strength` and stops `DEAD_BAND` short of `radius`, so a
## pair parts once and then rests. A unit walking under an order is pushed at most `WALK_SHARE` of its
## walk speed, so its walk always gains and the stall check never sees it held; a unit in melee range
## of its attack target is never pushed out of that range. Dead, stunned and feeding units are never
## pushed (stunned covers a meal held by a feed); every living unit pushes. Units still do not collide
## with each other: walls stop a pushed unit as they stop a walking one.

## Overlaps smaller than this are left alone, so two units at rest do not nudge each other for ever.
const DEAD_BAND: float = 0.03
## The overlap, as a share of `radius`, at which the push reaches `strength`.
const FULL_AT: float = 0.5
## A walking unit is pushed at most this share of its walk speed.
const WALK_SHARE: float = 0.5
## A unit in melee range of its attack target may be pushed out to this far short of that range.
const RANGE_MARGIN: float = 0.05

## Every unit with a `Separation` in the tree; at most a few, so a plain list is enough.
static var _all: Array[Unit] = []

## Other units closer than this, flat, are pushed away from.
@export var radius: float = 0.7
## The fastest push, in metres per second.
@export var strength: float = 2.0

@onready var _unit: Unit = get_parent()
@onready var _melee: MeleeAttack = get_node_or_null(^"../Melee")


func _enter_tree() -> void:
	var unit: Unit = get_parent() as Unit
	if unit != null and not _all.has(unit):
		_all.append(unit)


func _exit_tree() -> void:
	_all.erase(get_parent())


## The flat velocity, Y zero, that moves the unit apart from its neighbours this frame.
func push() -> Vector3:
	if not _unit.is_alive() or _unit.is_stunned() or _unit.is_feeding():
		return Vector3.ZERO
	var here: Vector3 = _unit.global_position
	var total := Vector2.ZERO
	for other: Unit in _all:
		if other == _unit or not other.is_alive() or not other.is_inside_tree():
			continue
		var away := Vector2(here.x - other.global_position.x, here.z - other.global_position.z)
		var gap: float = away.length()
		var overlap: float = radius - gap
		if overlap <= DEAD_BAND:
			continue
		var direction: Vector2 = away / gap if gap > 0.001 else _apart_from(other)
		total += direction * strength * minf(overlap / (radius * FULL_AT), 1.0)
	if total == Vector2.ZERO:
		return Vector3.ZERO
	var cap: float = strength
	if _unit.is_moving():
		cap = minf(cap, _unit.walk_speed() * WALK_SHARE)
	total = total.limit_length(cap)
	return _within_reach(Vector3(total.x, 0.0, total.y))


## A fixed direction apart from a unit at the very same spot: the pair's instance ids choose the
## line, and the higher id takes one end and the lower the other.
func _apart_from(other: Unit) -> Vector2:
	var mine: int = _unit.get_instance_id()
	var theirs: int = other.get_instance_id()
	var angle: float = deg_to_rad(float(absi(mine ^ theirs) % 360))
	var direction := Vector2.from_angle(angle)
	return direction if mine > theirs else -direction


## `velocity` cut short so this frame's move leaves the unit no farther from its attack target than
## it is now, or than just inside melee range, whichever is farther.
func _within_reach(velocity: Vector3) -> Vector3:
	var target: Unit = _unit.attack_target()
	if _melee == null or target == null or _unit.current_order() != Unit.Order.ATTACK or not _melee.in_range(target):
		return velocity
	var centre := Vector2(target.global_position.x, target.global_position.z)
	var here := Vector2(_unit.global_position.x, _unit.global_position.z)
	var limit: float = maxf((here - centre).length(), _melee.attack_range - RANGE_MARGIN)
	var delta: float = get_physics_process_delta_time()
	var next: Vector2 = here + Vector2(velocity.x, velocity.z) * delta
	if (next - centre).length() <= limit:
		return velocity
	var kept: Vector2 = (centre + (next - centre).normalized() * limit - here) / delta
	return Vector3(kept.x, 0.0, kept.y)
