class_name Encounter
extends Node
## The fight in a room: spawns the room's crusaders, a sergeant at each of its sergeant markers, unless
## the room was cleared before; tells whether a fight is on; signals the room cleared once, when its last
## enemy falls, and records that in the game state; raises the party's fallen at once then, and otherwise
## after `calm_time` without a fight; and marks the enemies the selected member can feed on. Nothing
## advances while Álvar is down or while `paused`.

## The room's last enemy fell. Not emitted for a room entered already cleared.
signal cleared

const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")
const SERGEANT: PackedScene = preload("res://scenes/units/crusader_sergeant.tscn")

## Seconds without a fight before fallen companions rise.
@export var calm_time: float = 3.0

## While true the fight does not advance; the feed marks still follow, so they are right while the
## player plans.
var paused: bool = false
var enemies: Array[Unit] = []

var _party: Party
var _state: GameState
## The state flag recording that this room was cleared.
var _cleared_flag: StringName
var _cleared: bool = false
## Seconds since a fight was last on or a party member last fell.
var _calm_for: float = 0.0


## Follows `party`'s falls and selection. Called once, before anything else connects to `party`, so the
## marks are right by the time others hear of a change.
func watch(party: Party) -> void:
	_party = party
	party.member_fell.connect(_on_member_fell)
	party.selection_changed.connect(_on_selection_changed)


## Starts the fight of `room`, with its enemies added under `parent` unless `state` says the room was
## cleared. A room without enemies has nothing to clear, so it starts cleared too. The last fight's
## enemies must already be freed.
func begin(room: Room, state: GameState, parent: Node) -> void:
	_state = state
	enemies.clear()
	_calm_for = 0.0
	_cleared_flag = StringName("%s_cleared" % room.room_id)
	var markers: Array[Marker3D] = room.enemy_markers()
	var was_cleared: bool = state.has_flag(_cleared_flag)
	_cleared = was_cleared or markers.is_empty()
	if was_cleared:
		return
	for marker: Marker3D in markers:
		var scene: PackedScene = SERGEANT if room.sergeant_spawns.has(StringName(marker.name)) else CRUSADER
		var enemy: Unit = scene.instantiate()
		parent.add_child(enemy)
		enemy.global_transform = marker.global_transform
		enemies.append(enemy)


## True from the fall of the room's last enemy, or from entering a cleared room, until the next fight.
func is_cleared() -> bool:
	return _cleared


## True while any living enemy is attacking someone.
func fight_is_on() -> bool:
	for enemy: Unit in enemies:
		if enemy.is_alive() and enemy.attack_target() != null:
			return true
	return false


func enemies_alive() -> int:
	var alive: int = 0
	for enemy: Unit in enemies:
		if enemy.is_alive():
			alive += 1
	return alive


## Marks exactly the living enemies the selected member can feed on, whatever its Blood; none while
## Álvar is down.
func update_feed_marks() -> void:
	var feeder: Unit = _party.selected if _leader_alive() else null
	for enemy: Unit in enemies:
		enemy.set_feed_mark(feeder != null and feeder.can_feed_on(enemy))


func _physics_process(delta: float) -> void:
	if _state == null:
		return
	if not paused:
		_advance(delta)
	update_feed_marks()


## Signals a cleared room once and raises the fallen at once; otherwise raises them after `calm_time`
## without a fight. Nothing happens while Álvar is down.
func _advance(delta: float) -> void:
	if not _leader_alive():
		return
	if not _cleared and enemies_alive() == 0:
		_cleared = true
		_state.set_flag(_cleared_flag)
		cleared.emit()
		_party.revive_fallen()
	if fight_is_on():
		_calm_for = 0.0
		return
	_calm_for += delta
	if _calm_for >= calm_time:
		_party.revive_fallen()


func _leader_alive() -> bool:
	return _party != null and _party.leader != null and _party.leader.is_alive()


func _on_member_fell(_unit: Unit) -> void:
	_calm_for = 0.0
	update_feed_marks()


func _on_selection_changed(_unit: Unit) -> void:
	update_feed_marks()
