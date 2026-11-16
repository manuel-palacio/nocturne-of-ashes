class_name Room
extends Node3D
## A place the party can be in: its floor and walls, the entries the party arrives by and the markers
## where its enemies stand. An entry is a `Marker3D` named `Entry_<name>` with two `Marker3D` children,
## `Companion1` and `Companion2`, for the companions; every room has `Entry_start`. Enemy markers are
## `Marker3D` children named `EnemySpawn<N>`.

const ENTRY_PREFIX: String = "Entry_"
const START: StringName = &"start"
const ENEMY_PREFIX: String = "EnemySpawn"

@export var room_id: StringName
## The enemy markers that get a sergeant instead of a crusader.
@export var sergeant_spawns: Array[StringName] = []


## The entry called `entry_name`; `Entry_start`, with a warning, when the room has no such entry.
func entry(entry_name: StringName) -> Marker3D:
	var found := get_node_or_null(NodePath(ENTRY_PREFIX + entry_name)) as Marker3D
	if found == null:
		push_warning("Room %s has no entry %s; arriving at %s instead" % [room_id, entry_name, START])
		found = get_node(NodePath(ENTRY_PREFIX + START)) as Marker3D
	return found


## The enemy markers, in scene order.
func enemy_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child: Node in get_children():
		if child is Marker3D and child.name.begins_with(ENEMY_PREFIX):
			markers.append(child)
	return markers
