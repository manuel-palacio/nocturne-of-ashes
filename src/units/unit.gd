class_name Unit
extends CharacterBody3D
## The body every character uses: walks where it is ordered over the navmesh and dies with its stats.

signal died(unit: Unit)
signal arrived

@export var stats: Stats
@export var faction: StringName = &"player"
@export var move_speed: float = 4.0
@export var display_name: String = ""

var _moving: bool = false

@onready var _agent: NavigationAgent3D = $Agent
@onready var _body: MeshInstance3D = $Body
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)


func _physics_process(_delta: float) -> void:
	if not _moving:
		return
	if _agent.is_navigation_finished():
		stop()
		arrived.emit()
		return
	var to_next: Vector3 = _agent.get_next_path_position() - global_position
	to_next.y = 0.0
	velocity = to_next.normalized() * move_speed
	move_and_slide()


## Walks to the reachable navmesh point nearest to `target`. Ignored once dead.
func order_move(target: Vector3) -> void:
	if not is_alive():
		return
	var map: RID = _agent.get_navigation_map()
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, target)
	# The navmesh surface floats above the floor; the agent's path points are lowered by
	# path_height_offset, so the target must be too or it is never "reached".
	_agent.target_position = on_mesh - Vector3(0.0, _agent.path_height_offset, 0.0)
	_moving = true


func stop() -> void:
	_moving = false
	velocity = Vector3.ZERO


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
