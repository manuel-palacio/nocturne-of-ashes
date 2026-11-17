class_name Mover
extends Node
## Walks its `Unit` over the navmesh: decides where to head each frame, while the unit decides
## whether to walk and how fast. Each frame the unit calls `steer()` before moving its body and
## `after_move()` once it has moved.

signal arrived
signal stalled

## A walk that has moved the unit less than this in `_STALL_TIME` is dropped with a warning.
const _STALL_DISTANCE: float = 0.1
const _STALL_TIME: float = 1.0
## A walk still waiting to be planned after this many seconds is dropped with a warning: its map
## never became ready, or the unit never landed.
const _PLAN_TIME: float = 5.0

## When false, a walk that makes no progress carries on: a chase re-aims on its own instead.
var stall_check: bool = true

var _walking: bool = false
## True while the walk waits for the navigation map to contain a navmesh, or for the landing.
var _pending: bool = false
var _destination: Vector3
var _heading: Vector3
var _steered: bool = false
var _stall_from: Vector3
var _stall_timer: float = 0.0
## Seconds the walk has waited to be planned.
var _waiting_for: float = 0.0

@onready var _unit: Unit = get_parent()
@onready var _agent: NavigationAgent3D = $"../Agent"


## Walks to the reachable navmesh point nearest to `target`.
## A walk started before the navigation map has synced, or in the air, is held until it can be planned,
## for at most `_PLAN_TIME` seconds of the unit's physics; then it is dropped with a warning.
func walk_to(target: Vector3) -> void:
	_destination = target
	_pending = true
	_walking = true
	_waiting_for = 0.0
	_plan()


## Stops walking.
func halt() -> void:
	_walking = false
	_pending = false
	_steered = false


func is_walking() -> bool:
	return _walking


## Where the latest walk was ordered to, before snapping to the navmesh.
func destination() -> Vector3:
	return _destination


## The flat unit direction towards the next path point, as of the latest `steer()`.
func heading() -> Vector3:
	return _heading


## Advances the walk by one frame. Returns whether the unit walks this frame; `heading()` then says where.
## Emits `arrived` when the path is done.
func steer() -> bool:
	_steered = false
	if not _walking:
		return false
	if _pending:
		_plan()
		if _pending:
			# Only frames that tried to plan count, so a stun or a hold does not use the time up.
			_wait_for_plan(get_physics_process_delta_time())
		return false
	if _agent.is_navigation_finished():
		halt()
		arrived.emit()
		return false
	var to_next: Vector3 = _agent.get_next_path_position() - _unit.global_position
	to_next.y = 0.0
	_heading = to_next.normalized()
	_steered = true
	return true


## Called once the unit has moved its body this frame. `was_on_floor` is the floor state before the move.
func after_move(delta: float, was_on_floor: bool) -> void:
	# A walk planned in the air holds the wrong height gap; plan it again on landing.
	if _walking and not was_on_floor and _unit.is_on_floor():
		_pending = true
	if _steered and stall_check:
		_check_progress(delta)
	# A frame in which the unit did not steer, such as while it is held still, never counts as a stall.
	_steered = false


func _plan() -> void:
	var map: RID = _agent.get_navigation_map()
	# Before the map holds a navmesh, closest-point queries answer with the origin.
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	if not NavigationServer3D.map_get_closest_point_owner(map, _destination).is_valid():
		return
	# The height gap below is measured from where the feet come to rest, so wait for the landing.
	if not _unit.is_on_floor():
		return
	# The baked surface rarely lies exactly at the unit's feet. The agent compares positions in 3D,
	# so its path points are lowered by the measured gap, and so is the target.
	var surface_here: Vector3 = NavigationServer3D.map_get_closest_point(map, _unit.global_position)
	_agent.path_height_offset = surface_here.y - _unit.global_position.y
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, _destination)
	_agent.target_position = on_mesh - Vector3(0.0, _agent.path_height_offset, 0.0)
	_pending = false
	_waiting_for = 0.0
	_stall_from = _unit.global_position
	_stall_timer = 0.0


func _wait_for_plan(delta: float) -> void:
	_waiting_for += delta
	if _waiting_for >= _PLAN_TIME:
		push_warning("Unit %s could not plan its move order in %.0f s; stopping." % [_unit.name, _PLAN_TIME])
		halt()
		stalled.emit()


func _check_progress(delta: float) -> void:
	var at: Vector3 = _unit.global_position
	if Vector2(at.x - _stall_from.x, at.z - _stall_from.z).length() >= _STALL_DISTANCE:
		_stall_from = at
		_stall_timer = 0.0
		return
	_stall_timer += delta
	if _stall_timer >= _STALL_TIME:
		push_warning("Unit %s made no progress on its move order for %.1f s; stopping." % [_unit.name, _STALL_TIME])
		halt()
		stalled.emit()
