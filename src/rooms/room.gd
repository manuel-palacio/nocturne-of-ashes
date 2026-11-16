class_name Room
extends Node3D
## A place the party can be in: its floor and walls, the entries the party arrives by and the markers
## where its enemies stand. An entry is a `Marker3D` named `Entry_<name>` with two `Marker3D` children,
## `Companion1` and `Companion2`, for the companions; every room has `Entry_start`. Enemy markers are
## `Marker3D` children named `EnemySpawn<N>`. The characters to talk to are `Npc` children.

const ENTRY_PREFIX: String = "Entry_"
const START: StringName = &"start"
const ENEMY_PREFIX: String = "EnemySpawn"

@export var room_id: StringName
## The enemy markers that get a sergeant instead of a crusader.
@export var sergeant_spawns: Array[StringName] = []


## The entry called `entry_name`; `Entry_start`, with a warning, when the room has no such entry; null,
## with an error, when the room has no `Entry_start` either.
func entry(entry_name: StringName) -> Marker3D:
	var found := get_node_or_null(NodePath(ENTRY_PREFIX + entry_name)) as Marker3D
	if found != null:
		return found
	var start := get_node_or_null(NodePath(ENTRY_PREFIX + START)) as Marker3D
	if start == null:
		push_error("Room %s has no %s%s (asked for entry %s); the party arrives at the room's origin"
				% [room_id, ENTRY_PREFIX, START, entry_name])
		return null
	push_warning("Room %s has no entry %s; arriving at %s instead" % [room_id, entry_name, START])
	return start


## Where the companion `index` (1 or 2) stands on arriving at `at_entry`: its `Companion<index>`
## marker, or, with an error, the entry itself when it has none.
func companion_marker(at_entry: Marker3D, index: int) -> Node3D:
	var found := at_entry.get_node_or_null(NodePath("Companion%d" % index)) as Node3D
	if found == null:
		push_error("Entry %s of room %s has no Companion%d; that companion arrives at the entry"
				% [at_entry.name, room_id, index])
		return at_entry
	return found


## The characters to talk to that are children of the room, in scene order.
func npcs() -> Array[Npc]:
	var found: Array[Npc] = []
	for child: Node in get_children():
		if child is Npc:
			found.append(child)
	return found


## The enemy markers, in scene order.
func enemy_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child: Node in get_children():
		if child is Marker3D and child.name.begins_with(ENEMY_PREFIX):
			markers.append(child)
	return markers
