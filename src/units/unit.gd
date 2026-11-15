class_name Unit
extends CharacterBody3D
## The body every character uses: walks where it is ordered over the navmesh and dies with its stats.

signal died(unit: Unit)
signal arrived
signal attack_ended

@export var stats: Stats
@export var faction: StringName = &"player"
@export var move_speed: float = 4.0
@export var display_name: String = ""

## An order that has moved the unit less than this in `_STALL_TIME` is dropped with a warning.
const _STALL_DISTANCE: float = 0.1
const _STALL_TIME: float = 1.0
## While chasing, the walk is re-aimed once the target has moved this far from where it was headed.
const _CHASE_RETARGET: float = 0.5

var _moving: bool = false
## True while the order waits for the navigation map to contain a navmesh.
var _order_pending: bool = false
var _ordered_target: Vector3
var _stall_from: Vector3
var _stall_timer: float = 0.0
var _attack_target: Unit

@onready var _agent: NavigationAgent3D = $Agent
@onready var _body: MeshInstance3D = $Body
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _melee: MeleeAttack = get_node_or_null(^"Melee")


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)


func _physics_process(delta: float) -> void:
	# A freed target compares equal to null, so test for "no reference held" with is_same.
	if not is_same(_attack_target, null):
		_pursue()
	if not _moving:
		return
	if _order_pending:
		_apply_order()
		return
	var chasing: bool = not is_same(_attack_target, null)
	if _agent.is_navigation_finished():
		_halt()
		if not chasing:
			arrived.emit()
		return
	var to_next: Vector3 = _agent.get_next_path_position() - global_position
	to_next.y = 0.0
	velocity = to_next.normalized() * move_speed
	move_and_slide()
	# A chase re-aims on its own, and a blocked chaser keeps trying.
	if not chasing:
		_check_progress(delta)


## Walks to the reachable navmesh point nearest to `target`. Ignored once dead.
## An order given before the navigation map has synced is held until it has.
func order_move(target: Vector3) -> void:
	if not is_alive():
		return
	_attack_target = null
	_walk_to(target)


## Chases `target` into melee range and strikes it until it dies. Ignored for friends and the dead.
func order_attack(target: Unit) -> void:
	if not is_alive() or _melee == null or target == null or not target.is_alive() or not is_hostile_to(target):
		return
	_attack_target = target
	_walk_to(target.global_position)


func attack_target() -> Unit:
	return _attack_target if is_instance_valid(_attack_target) else null


## Halts and drops any attack.
func stop() -> void:
	_attack_target = null
	_halt()


func _walk_to(target: Vector3) -> void:
	_ordered_target = target
	_order_pending = true
	_moving = true
	_apply_order()


func _halt() -> void:
	_moving = false
	_order_pending = false
	velocity = Vector3.ZERO


func _apply_order() -> void:
	var map: RID = _agent.get_navigation_map()
	# Before the map holds a navmesh, closest-point queries answer with the origin.
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	if not NavigationServer3D.map_get_closest_point_owner(map, _ordered_target).is_valid():
		return
	# The baked surface rarely lies exactly at the unit's feet. The agent compares positions in 3D,
	# so its path points are lowered by the measured gap, and so is the target.
	var surface_here: Vector3 = NavigationServer3D.map_get_closest_point(map, global_position)
	_agent.path_height_offset = surface_here.y - global_position.y
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, _ordered_target)
	_agent.target_position = on_mesh - Vector3(0.0, _agent.path_height_offset, 0.0)
	_order_pending = false
	_stall_from = global_position
	_stall_timer = 0.0


func _pursue() -> void:
	if not is_instance_valid(_attack_target) or not _attack_target.is_alive():
		stop()
		attack_ended.emit()
		return
	var target_at: Vector3 = _attack_target.global_position
	if not _melee.in_range(_attack_target):
		var drift: Vector3 = target_at - _ordered_target
		# Re-aim only when the target has moved, so a path ending short of it does not re-path each frame.
		if Vector2(drift.x, drift.z).length() > _CHASE_RETARGET:
			_walk_to(target_at)
		return
	_halt()
	var facing: Vector3 = target_at - global_position
	if Vector2(facing.x, facing.z).length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)
	if _melee.ready_to_swing():
		_melee.try_hit(_attack_target)


func _check_progress(delta: float) -> void:
	if Vector2(global_position.x - _stall_from.x, global_position.z - _stall_from.z).length() >= _STALL_DISTANCE:
		_stall_from = global_position
		_stall_timer = 0.0
		return
	_stall_timer += delta
	if _stall_timer >= _STALL_TIME:
		push_warning("Unit %s made no progress on its move order for %.1f s; stopping." % [name, _STALL_TIME])
		stop()


func is_moving() -> bool:
	return _moving


func is_alive() -> bool:
	return not stats.is_dead()


func is_hostile_to(other: Unit) -> bool:
	return faction != other.faction


func _on_stats_died() -> void:
	stop()
	_collision.set_deferred(&"disabled", true)
	_body.rotation.x = PI / 2.0
	died.emit(self)
