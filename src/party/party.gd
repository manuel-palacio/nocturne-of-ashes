class_name Party
extends Node
## The party: its members (one to three), the leader Álvar, whose fall ends the round, and the selected
## member. The selected member's brain is off and the other living members follow it. Raises the
## fallen when asked. Builds members from a `GameState` (their Gifts and vitals), writes their vitals
## back, and keeps their vitals as a room was entered for a restart. While a room is live it follows the
## state: a Gift learned is added to its member at once, and a member who joins is spawned in the room
## (the room only says where). It knows nothing of enemies.

## A member became the selected one: a living one, or the leader when nobody lives.
signal selection_changed(unit: Unit)
## A member fell.
signal member_fell(unit: Unit)
## A fallen member rose.
signal member_rose(unit: Unit)
## A member joined mid-room and was spawned and added.
signal member_added(unit: Unit)
## A member's Gifts changed because it learned one.
signal gifts_changed(unit: Unit)

## Each member's scene, by `Unit.member_id`.
const SCENES: Dictionary = {
	&"alvar": preload("res://scenes/units/alvar.tscn"),
	&"zahra": preload("res://scenes/units/zahra.tscn"),
	&"gonzalo": preload("res://scenes/units/gonzalo.tscn"),
}

## In the order they were added, the leader first.
var members: Array[Unit] = []
## Álvar: the member whose `member_id` is `GameState.LEADER`.
var leader: Unit
var selected: Unit

## Each member's vitals in the state as the room was entered, for a restart.
var _entry_vitals: Dictionary = {}  # StringName member -> Vector2i
## Every Gift of each member's scene, in its order, by `Unit.member_id`: what known Gifts are taken from.
var _scene_gifts: Dictionary = {}  # StringName member -> Array[Gift]
## The state, room, entry and units' parent of the live room, set by `begin_room()`.
var _state: GameState
var _room: Room
var _entry: Marker3D
var _parent: Node
## Where each member who joined this frame will stand, chosen as they joined: by the time they are
## spawned, the same conversation may have hidden the character they stand beside.
var _arrivals: Dictionary = {}  # StringName member -> Vector3


## Forgets every member; the caller frees their nodes.
func clear() -> void:
	for member: Unit in members:
		if is_instance_valid(member):
			member.died.disconnect(_on_member_died)
			member.revived.disconnect(_on_member_revived)
	members.clear()
	_scene_gifts.clear()
	leader = null
	selected = null


func add(member: Unit) -> void:
	members.append(member)
	if member.member_id == GameState.LEADER:
		leader = member
	member.died.connect(_on_member_died)
	member.revived.connect(_on_member_revived)


## Adds the member `member_id` to the party under `parent`, at `marker`, with only the Gifts it knows
## in `state`, in its scene's order, and the vitals `state` holds for it: health above the maximum is
## clamped to it, a stored 0 arrives as `Unit.risen_health()`.
func spawn(member_id: StringName, marker: Node3D, state: GameState, parent: Node) -> Unit:
	var unit: Unit = (SCENES[member_id] as PackedScene).instantiate()
	var gift_user: GiftUser = unit.get_node(^"Gifts")
	_scene_gifts[member_id] = gift_user.gifts.duplicate()
	gift_user.gifts = _known_gifts(member_id, state)
	var vitals: Vector2i = state.vitals(member_id)
	if vitals.y >= 0:
		# Set as the starting Blood, so the unit begins with it and its Fury sees no fall into it.
		var stats: Stats = unit.stats.duplicate()
		stats.starting_blood = vitals.y
		unit.stats = stats
	parent.add_child(unit)
	unit.global_transform = marker.global_transform
	if vitals.x >= 0:
		var health: int = Unit.risen_health(unit.stats) if vitals.x == 0 else mini(vitals.x, unit.stats.max_health)
		unit.stats.take_damage(unit.stats.max_health - health)
	add(unit)
	return unit


## Follows `state` while the party is in `room`, having arrived at `entry` (null when the room has
## none) with its units under `parent`: from now on a Gift learned in `state` is added to its member,
## and a member who joins is spawned. Both happen at the end of the frame, not inside the change: a
## conversation changes the state while it looks up its next line, and nothing the scene does in
## answer (such as setting up a figure) may run inside that lookup. Where a joiner will stand is chosen
## at once, while their character is still shown. Drops the state followed before.
## Called at each room start, once the party is spawned, as `Main` may hold a new state object then.
func begin_room(state: GameState, room: Room, entry: Marker3D, parent: Node) -> void:
	if _state != null and _state.member_joined.is_connected(_on_member_joined):
		_state.member_joined.disconnect(_on_member_joining)
		_state.member_joined.disconnect(_on_member_joined)
		_state.gift_learned.disconnect(_on_gift_learned)
	_state = state
	_room = room
	_entry = entry
	_parent = parent
	_arrivals.clear()
	state.member_joined.connect(_on_member_joining)
	state.member_joined.connect(_on_member_joined, CONNECT_DEFERRED)
	state.gift_learned.connect(_on_gift_learned, CONNECT_DEFERRED)


## Stores each member's health and Blood in `state`; a fallen member's health as `Unit.risen_health()`.
func record(state: GameState) -> void:
	for member: Unit in members:
		var health: int = member.stats.health
		if not member.is_alive():
			health = Unit.risen_health(member.stats)
		state.set_vitals(member.member_id, health, member.stats.blood)


## Called on entering a room, once the members are spawned. In a `restful` room, one without living
## enemies, the party rests: every member's health is restored to its maximum, the fallen raised first.
## Blood is not changed. Elsewhere nothing changes.
func arrive(restful: bool) -> void:
	if not restful:
		return
	for member: Unit in members:
		member.revive()
		member.stats.heal(member.stats.max_health - member.stats.health)


## Remembers the members' vitals in `state` as the room is entered.
func remember_entry_vitals(state: GameState) -> void:
	_entry_vitals.clear()
	for member: Unit in members:
		_entry_vitals[member.member_id] = state.vitals(member.member_id)


## Puts back into `state` the vitals remembered on entering the room.
func restore_entry_vitals(state: GameState) -> void:
	for member: StringName in _entry_vitals:
		var vitals: Vector2i = _entry_vitals[member]
		state.set_vitals(member, vitals.x, vitals.y)


## Makes `unit` the selected member and sets the other living members following it.
## Ignored unless `unit` is a living member, and while the leader is down.
func select(unit: Unit) -> void:
	if not leader_alive() or unit == null or not members.has(unit) or not unit.is_alive():
		return
	_make_selected(unit)


## Selects the next living member after the selected one, wrapping round. Ignored while the leader is down.
func select_next() -> void:
	if not leader_alive():
		return
	var at: int = members.find(selected)
	for step: int in range(1, members.size() + 1):
		var candidate: Unit = members[(at + step) % members.size()]
		if candidate.is_alive():
			select(candidate)
			return


func revive_fallen() -> void:
	for member: Unit in members:
		if not member.is_alive():
			member.revive()


## Whether the leader is there and alive.
func leader_alive() -> bool:
	return leader != null and leader.is_alive()


## Whether the leader is there and in the Fury.
func leader_in_fury() -> bool:
	return leader != null and leader.is_in_fury()


## Whether the leader is held by something of his own that leaving would break: the Fury, or a feed of
## his, walking to it or drinking. A companion's feed does not hold the party (`call_off_feeds()`).
func is_busy() -> bool:
	return leader != null and (leader.is_in_fury() or leader.feed_target() != null)


## Calls every companion off a feed, walking to it or drinking, as the party leaves the room.
func call_off_feeds() -> void:
	for member: Unit in members:
		if member != leader and member.feed_target() != null:
			member.stop()


## The selected member's brain is off; every other member's follows the selected one.
## The setter forgets the brain's chosen target, so `enabled` is only written when it changes.
func _steer_brain(member: Unit) -> void:
	var brain: CombatBrain = member.get_node(^"Brain")
	brain.leader = selected
	var wanted: bool = member != selected
	if brain.enabled != wanted:
		brain.enabled = wanted


func _make_selected(unit: Unit) -> void:
	selected = unit
	for member: Unit in members:
		member.set_selected_mark(member == unit)
		if member.is_alive():
			_steer_brain(member)
	selection_changed.emit(unit)


## Selection goes back to the leader when the selected companion falls; while the leader is down it
## goes to the first living member instead, or to the leader when nobody lives.
func _on_member_died(unit: Unit) -> void:
	member_fell.emit(unit)
	if unit == leader or unit != selected:
		return
	if leader_alive():
		select(leader)
		return
	for member: Unit in members:
		if member.is_alive():
			_make_selected(member)
			return
	_make_selected(leader)


## The Gifts of `member_id`'s scene that `state` says it knows, in the scene's order.
func _known_gifts(member_id: StringName, state: GameState) -> Array[Gift]:
	var known: Array[StringName] = state.known_gifts(member_id)
	var gifts: Array[Gift] = []
	for gift: Gift in _scene_gifts[member_id]:
		if known.has(gift.id):
			gifts.append(gift)
	return gifts


func _member(member_id: StringName) -> Unit:
	for member: Unit in members:
		if member.member_id == member_id:
			return member
	return null


## Spawns the member who joined beside their character in the room, or at the entry's next free
## companion marker, in `GameState.MEMBERS` order among the members, following the selected one.
func _on_member_joined(member_id: StringName) -> void:
	var arrival: Variant = _arrivals.get(member_id)
	_arrivals.erase(member_id)
	# Answered later in the frame: the state followed may have changed since, as a reload does.
	if _member(member_id) != null or not is_instance_valid(_room) or not _state.has_joined(member_id):
		return
	var marker: Node3D = _arrival_marker(members.size())
	var unit: Unit = spawn(member_id, marker, _state, _parent)
	unit.global_position = arrival if arrival != null else _room.arrival_point(unit.display_name, marker)
	# `spawn()` appended it; it goes where `MEMBERS` puts it among those present.
	members.erase(unit)
	var rank: int = GameState.MEMBERS.find(member_id)
	var at: int = 0
	while at < members.size() and GameState.MEMBERS.find(members[at].member_id) < rank:
		at += 1
	members.insert(at, unit)
	# A restart of the room brings them back as they joined.
	_entry_vitals[member_id] = _state.vitals(member_id)
	# While the leader is down this follows a fallen leader, as the others do; the round ends on a reload.
	if selected != null:
		_steer_brain(unit)
	member_added.emit(unit)


## Chooses, as `member_id` joins, where they will stand once spawned.
func _on_member_joining(member_id: StringName) -> void:
	if _member(member_id) != null or not is_instance_valid(_room) or _arrivals.has(member_id):
		return
	# Those already waiting to be spawned this frame take the markers before this one.
	var marker: Node3D = _arrival_marker(members.size() + _arrivals.size())
	_arrivals[member_id] = _room.arrival_point(_display_name(member_id), marker)


## The companion marker of the entry for a member arriving when `present` members are there.
func _arrival_marker(present: int) -> Node3D:
	if _entry == null:
		return _room
	return _room.companion_marker(_entry, clampi(present, 1, 2))


## The name the scene of `member_id` gives its unit, read without making one.
static func _display_name(member_id: StringName) -> String:
	var scene: SceneState = (SCENES[member_id] as PackedScene).get_state()
	for i: int in scene.get_node_property_count(0):
		if scene.get_node_property_name(0, i) == &"display_name":
			return scene.get_node_property_value(0, i)
	return ""


func _on_gift_learned(member_id: StringName, _gift: StringName) -> void:
	var unit: Unit = _member(member_id)
	if unit == null:
		return
	(unit.get_node(^"Gifts") as GiftUser).replace_gifts(_known_gifts(member_id, _state))
	gifts_changed.emit(unit)


func _on_member_revived(unit: Unit) -> void:
	_steer_brain(unit)
	member_rose.emit(unit)
