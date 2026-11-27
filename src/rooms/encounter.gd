class_name Encounter
extends Node
## The fight in a room: spawns the room's crusaders, a sergeant at each of its sergeant markers, unless
## the room was cleared before; tells whether a fight is on; signals the room cleared once, when its last
## enemy falls, and records that in the game state; raises the party's fallen at once then, and otherwise
## after `calm_time` without a fight; and marks the enemies the selected member can feed on. A room is
## one fight: when its first enemy falls, or `ALERT_TIME` seconds after the first blow lands on anyone,
## whichever comes first, every living enemy is alerted (`CombatBrain.alerted`) and comes for the party
## from wherever it stands. Nothing advances while Álvar is down or while `paused`.

## The room's last enemy fell. Not emitted for a room entered already cleared.
signal cleared

const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")
const SERGEANT: PackedScene = preload("res://scenes/units/crusader_sergeant.tscn")
## Seconds after the first blow of a room's fight before all its enemies are alerted.
const ALERT_TIME: float = 10.0

## Seconds without a fight before fallen companions rise.
@export var calm_time: float = 3.0
## The share of its tuned health each enemy of the next `begin()` has, as a guard tired by Álvar's
## falls (`Main.guard_health()`); 1 is the guard as tuned.
var guard_health: float = 1.0

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
## Whether the room's enemies have all been alerted.
var _alerted: bool = false
## Seconds of fight since the first blow landed on an enemy or a party member, until the room is
## cleared; negative before it.
var _since_first_blow: float = -1.0


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
	_alerted = false
	_since_first_blow = -1.0
	_cleared_flag = StringName("%s_cleared" % room.room_id)
	var markers: Array[Marker3D] = room.enemy_markers()
	var was_cleared: bool = state.has_flag(_cleared_flag)
	_cleared = was_cleared or markers.is_empty()
	if was_cleared:
		return
	for member: Unit in _party.members:
		if not member.was_hit.is_connected(_on_blow):
			member.was_hit.connect(_on_blow)
	for marker: Marker3D in markers:
		var scene: PackedScene = SERGEANT if room.sergeant_spawns.has(StringName(marker.name)) else CRUSADER
		var enemy: Unit = scene.instantiate()
		if guard_health < 1.0:
			# Its own copy, which the enemy's `_ready()` copies again and fills to this maximum.
			var stats: Stats = enemy.stats.duplicate()
			stats.max_health = maxi(roundi(stats.max_health * guard_health), 1)
			enemy.stats = stats
		parent.add_child(enemy)
		enemy.global_transform = marker.global_transform
		enemy.was_hit.connect(_on_blow)
		enemies.append(enemy)


## True from the fall of the room's last enemy, or from entering a cleared room, until the next fight.
func is_cleared() -> bool:
	return _cleared


## Whether every enemy of the room has been alerted, as `Encounter` describes.
func is_alerted() -> bool:
	return _alerted


## Seconds of fight since the first blow of this round landed, on an enemy or a party member; it does
## not advance while the fight is held, while Álvar is down or once the room is cleared. Negative
## before the first blow.
func fight_time() -> float:
	return _since_first_blow


## Whether `enemy` is one of the guard's sergeants.
static func is_sergeant(enemy: Unit) -> bool:
	return enemy.scene_file_path == SERGEANT.resource_path


## Whether the fight has left a mark: an enemy is hurt or has fallen.
func is_disturbed() -> bool:
	return enemies.any(func(enemy: Unit) -> bool:
		return not enemy.is_alive() or enemy.stats.health < enemy.stats.max_health)


## True while any living enemy is attacking someone.
func fight_is_on() -> bool:
	for enemy: Unit in enemies:
		if enemy.is_alive() and enemy.attack_target() != null:
			return true
	return false


## Whether a living enemy stands within `radius` of `point`, flat on XZ.
func enemy_within(point: Vector3, radius: float) -> bool:
	for enemy: Unit in enemies:
		var gap: Vector3 = enemy.global_position - point
		if enemy.is_alive() and Vector2(gap.x, gap.z).length() <= radius:
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
	if not _cleared and _since_first_blow >= 0.0:
		_since_first_blow += delta
	if not _cleared and not _alerted:
		if enemies_alive() < enemies.size() or _since_first_blow >= ALERT_TIME:
			_alert()
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


## Every living enemy comes for the party: its brain, when it has one, engages at any distance.
func _alert() -> void:
	_alerted = true
	for enemy: Unit in enemies:
		var brain := enemy.get_node_or_null(^"Brain") as CombatBrain
		if enemy.is_alive() and brain != null:
			brain.alerted = true


## The first blow of the fight, on an enemy or a party member, starts the count to `ALERT_TIME`.
func _on_blow(_amount: int, _source: Unit) -> void:
	if _since_first_blow < 0.0:
		_since_first_blow = 0.0


func _leader_alive() -> bool:
	return _party != null and _party.leader != null and _party.leader.is_alive()


func _on_member_fell(_unit: Unit) -> void:
	_calm_for = 0.0
	update_feed_marks()


func _on_selection_changed(_unit: Unit) -> void:
	update_feed_marks()
