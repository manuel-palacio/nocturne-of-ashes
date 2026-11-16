class_name Unit
extends CharacterBody3D
## The body every character uses: carries out its orders, walking through its `Mover`, and dies with its stats.

signal died(unit: Unit)
signal arrived
signal attack_ended

@export var stats: Stats
@export var faction: StringName = &"player"
@export var move_speed: float = 4.0
@export var display_name: String = ""

## What the unit was last told to do; NONE once it is done, stopped or dead.
enum Order { NONE, MOVE, ATTACK }

## While chasing, the walk is re-aimed once the target has moved this far from where it was headed.
const _CHASE_RETARGET: float = 0.5

var _order: Order = Order.NONE
var _attack_target: Unit
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _mover: Mover = $Mover
@onready var _body: MeshInstance3D = $Body
@onready var _melee: MeleeAttack = get_node_or_null(^"Melee")


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)
	_mover.arrived.connect(_on_mover_arrived)
	_mover.stalled.connect(stop)


func _physics_process(delta: float) -> void:
	if _order == Order.ATTACK:
		_pursue()
	if _mover.steer():
		var step: Vector3 = _mover.heading() * move_speed
		velocity.x = step.x
		velocity.z = step.z
	var was_on_floor: bool = is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity * delta
	move_and_slide()
	_mover.after_move(delta, was_on_floor)


func current_order() -> Order:
	return _order


## Walks to the reachable navmesh point nearest to `target`. Ignored once dead.
## An order given before the navigation map has synced is held until it has.
func order_move(target: Vector3) -> void:
	if not is_alive():
		return
	_attack_target = null
	_order = Order.MOVE
	# A plain walk that makes no progress is dropped with a warning.
	_mover.stall_check = true
	_mover.walk_to(target)


## Chases `target` into melee range and strikes it until it dies. Ignored for friends and the dead.
func order_attack(target: Unit) -> void:
	if not is_alive() or _melee == null or target == null or not target.is_alive() or not is_hostile_to(target):
		return
	_attack_target = target
	_order = Order.ATTACK
	# A chase re-aims on its own, and a blocked chaser keeps trying.
	_mover.stall_check = false
	_mover.walk_to(target.global_position)


func attack_target() -> Unit:
	return _attack_target if is_instance_valid(_attack_target) else null


## Halts and drops any order.
func stop() -> void:
	_attack_target = null
	_order = Order.NONE
	_halt()


## Stops walking and stands still.
func _halt() -> void:
	_mover.halt()
	_stand_still()


## Drops the horizontal velocity; a fall in progress carries on.
func _stand_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## A finished path ends a move order. A chase path can end short of the target; the chase goes on.
func _on_mover_arrived() -> void:
	_stand_still()
	if _order == Order.MOVE:
		_order = Order.NONE
		arrived.emit()


func _pursue() -> void:
	if not is_instance_valid(_attack_target) or not _attack_target.is_alive():
		stop()
		attack_ended.emit()
		return
	var target_at: Vector3 = _attack_target.global_position
	if not _melee.in_range(_attack_target):
		var drift: Vector3 = target_at - _mover.destination()
		# Re-aim only when the target has moved, so a path ending short of it does not re-path each frame.
		if Vector2(drift.x, drift.z).length() > _CHASE_RETARGET:
			_mover.walk_to(target_at)
		return
	_halt()
	var facing: Vector3 = target_at - global_position
	if Vector2(facing.x, facing.z).length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)
	if _melee.ready_to_swing():
		_melee.try_hit(_attack_target)


func is_moving() -> bool:
	return _mover.is_walking()


func is_alive() -> bool:
	return not stats.is_dead()


func is_hostile_to(other: Unit) -> bool:
	return faction != other.faction


func _on_stats_died() -> void:
	stop()
	# Off every layer, so clicks and rays pass through the body, which still rests on the floor.
	set_deferred(&"collision_layer", 0)
	_body.rotation.x = PI / 2.0
	died.emit(self)
