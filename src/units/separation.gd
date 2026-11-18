class_name Separation
extends Node
## Keeps its `Unit` from standing inside another: each physics frame `push()` gives a small flat velocity
## away from every other living unit closer than `radius`, which the unit adds to its own for that one
## move. The push grows with the overlap up to `strength` and stops `DEAD_BAND` short of `radius`, so a
## pair parts once and then rests. A unit walking or attacking is pushed at most `WALK_SHARE` of its
## walk speed, so its walk always gains and the stall check never sees it held; an attacker is never
## pushed out of melee range, nor farther from its target when already out of it. Dead, stunned and
## feeding units are never pushed (stunned covers a meal held by a feed); every living unit pushes. Two units on the very same
## spot part along X, the one that entered the tree later towards +X, the same way every time. Units
## still do not collide with each other: walls stop a pushed unit as they stop a walking one.

## Overlaps smaller than this are left alone, so two units at rest do not nudge each other for ever.
const DEAD_BAND: float = 0.05
## The overlap, as a share of `radius`, at which the push reaches `strength`.
const FULL_AT: float = 0.5
## A walking or attacking unit is pushed at most this share of its walk speed.
const WALK_SHARE: float = 0.5
## An attacker may be pushed out to this far short of its melee range, and never farther from its target.
const RANGE_MARGIN: float = 0.05
## An attacker in melee range is not pushed nearer its target than this far short of the range.
const RING_DEPTH: float = 0.35

## Every unit with a `Separation` in the tree; at most a few, so a plain list is enough.
static var _all: Array[Unit] = []

## Other units closer than this, flat, are pushed away from.
@export var radius: float = 0.9
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
	var mine: int = _all.find(_unit)
	for index: int in _all.size():
		var other: Unit = _all[index]
		if index == mine or not other.is_alive() or not other.is_inside_tree():
			continue
		var away := Vector2(here.x - other.global_position.x, here.z - other.global_position.z)
		var gap: float = away.length()
		var overlap: float = radius - gap
		if overlap <= DEAD_BAND:
			continue
		var direction: Vector2 = away / gap if gap > 0.001 else Vector2(1.0 if mine > index else -1.0, 0.0)
		total += direction * strength * minf(overlap / (radius * FULL_AT), 1.0)
	if total == Vector2.ZERO:
		return Vector3.ZERO
	var cap: float = strength
	if _unit.is_moving() or _unit.current_order() == Unit.Order.ATTACK:
		cap = minf(cap, _unit.walk_speed() * WALK_SHARE)
	total = total.limit_length(cap)
	return _within_reach(Vector3(total.x, 0.0, total.y))


## For an attacker, `velocity` cut short so this frame's move keeps it within reach of its target.
## Out of range it is never pushed farther off. In range it stays between `RING_DEPTH` and
## `RANGE_MARGIN` short of its melee range, or where it already is beyond those, so a crowd of
## attackers spreads round the target instead of pressing into it.
func _within_reach(velocity: Vector3) -> Vector3:
	var target: Unit = _unit.attack_target()
	if _melee == null or target == null or _unit.current_order() != Unit.Order.ATTACK:
		return velocity
	var centre := Vector2(target.global_position.x, target.global_position.z)
	var here := Vector2(_unit.global_position.x, _unit.global_position.z)
	var gap: float = (here - centre).length()
	var outer: float = maxf(gap, _melee.attack_range - RANGE_MARGIN)
	var inner: float = 0.0
	if _melee.in_range(target):
		inner = minf(gap, _melee.attack_range - RING_DEPTH)
	var delta: float = get_physics_process_delta_time()
	var next: Vector2 = here + Vector2(velocity.x, velocity.z) * delta
	var next_gap: float = (next - centre).length()
	if (next_gap <= outer and next_gap >= inner) or next_gap < 0.001:
		return velocity
	var kept: Vector2 = (centre + (next - centre) / next_gap * clampf(next_gap, inner, outer) - here) / delta
	return Vector3(kept.x, 0.0, kept.y)
