class_name Unit
extends CharacterBody3D
## The body every character uses: carries out its orders, walking through its `Mover`, takes hits,
## carries timed status effects, dies with its stats and can be revived.

signal died(unit: Unit)
signal arrived
signal attack_ended
signal was_hit(amount: int, source: Unit)
signal effects_changed
signal revived(unit: Unit)

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
var _standing: Transform3D
var _fallen: Transform3D

@onready var _mover: Mover = $Mover
@onready var _body: MeshInstance3D = $Body
@onready var _melee: MeleeAttack = get_node_or_null(^"Melee")
@onready var _effects: Effects = $Effects


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)
	_mover.arrived.connect(_on_mover_arrived)
	_mover.stalled.connect(stop)
	_effects.changed.connect(effects_changed.emit)
	_standing = _body.transform
	# Lying on its side, lowered so its lowest point touches the floor at the unit's feet.
	var lying: Basis = Basis(Vector3.RIGHT, PI / 2.0)
	var lowest: float = (Transform3D(lying, Vector3.ZERO) * _body.get_aabb()).position.y
	_fallen = Transform3D(lying, Vector3(_standing.origin.x, -lowest, _standing.origin.z))


func _physics_process(delta: float) -> void:
	# A stunned unit keeps its order but neither chases, strikes nor walks; its Mover skips the frame.
	if is_stunned():
		_stand_still()
	else:
		if _order == Order.ATTACK:
			_pursue()
		if _mover.steer():
			var step: Vector3 = _mover.heading() * walk_speed()
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


## Metres per second while walking, with the effects applied.
func walk_speed() -> float:
	return move_speed * speed_multiplier()


## Deals `amount`, scaled by the damage this unit takes, and never less than 1. Returns the health
## removed, which `was_hit` also carries; 0 for amounts of 0 or less and for the dead.
func take_hit(amount: int, source: Unit = null) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var health_before: int = stats.health
	stats.take_damage(maxi(roundi(amount * damage_taken_multiplier()), 1))
	var removed: int = health_before - stats.health
	was_hit.emit(removed, source)
	return removed


## Brings a dead unit back with `health_fraction` of its maximum health, standing and with no order.
func revive(health_fraction: float = 0.3) -> void:
	if is_alive():
		return
	stats.revive(maxi(roundi(stats.max_health * health_fraction), 1))
	_body.transform = _standing
	# Deferred like the change on death, so a death and revival in one frame end on layer 2.
	set_deferred(&"collision_layer", 2)
	clear_effects()
	stop()
	revived.emit(self)


## Adds a copy of `effect`; one with the same id is replaced, which restarts its time.
func add_effect(effect: StatusEffect) -> void:
	_effects.add(effect)


func remove_effect(id: StringName) -> void:
	_effects.remove(id)


func has_effect(id: StringName) -> bool:
	return _effects.has(id)


func clear_effects() -> void:
	_effects.clear()


func is_stunned() -> bool:
	return _effects.stuns()


func speed_multiplier() -> float:
	return _effects.speed_multiplier()


func damage_dealt_multiplier() -> float:
	return _effects.damage_dealt_multiplier()


func damage_taken_multiplier() -> float:
	return _effects.damage_taken_multiplier()


## The largest taunt radius among the active effects; 0 when none taunts.
func taunt_radius() -> float:
	return _effects.taunt_radius()


func is_moving() -> bool:
	return _mover.is_walking()


func is_alive() -> bool:
	return not stats.is_dead()


func is_hostile_to(other: Unit) -> bool:
	return faction != other.faction


func _on_stats_died() -> void:
	stop()
	clear_effects()
	# Off every layer, so clicks and rays pass through the body, which still rests on the floor.
	set_deferred(&"collision_layer", 0)
	_body.transform = _fallen
	died.emit(self)
