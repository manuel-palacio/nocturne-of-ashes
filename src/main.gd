class_name Main
extends Node3D
## The game's shell: loads rooms and runs them. In a room it spawns the members who have joined, with
## the health, Blood and Gifts the `GameState` gives them, and the room's crusaders, a sergeant among
## each group, unless the room was cleared before; wires camera, input and HUD, hands control to the
## party's selected member, raises fallen companions once a fight is over, marks the enemies the
## selected member can feed on, and restarts the room after Álvar's fall.
##
## The skirmish (`main.tscn`) always plays the vault with the whole party at full strength; the story
## (`game.tscn`) plays from a `GameState`.

## Emitted at the end of `start_room()` and `enter_room()`, once the room's units are in place.
signal room_started
## Emitted when a living party member becomes the selected one.
signal selection_changed(unit: Unit)
## Emitted once per round, when the last enemy falls; not when a room is entered already cleared.
signal room_cleared
## Emitted when a party member falls or rises.
signal party_changed
## Emitted when the world pause turns on or off.
signal pause_changed(paused: bool)

## Each party member's scene, by `Unit.member_id`.
const MEMBERS: Dictionary = {
	&"alvar": preload("res://scenes/units/alvar.tscn"),
	&"zahra": preload("res://scenes/units/zahra.tscn"),
	&"gonzalo": preload("res://scenes/units/gonzalo.tscn"),
}
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")
const SERGEANT: PackedScene = preload("res://scenes/units/crusader_sergeant.tscn")
## Every room, by its `Room.room_id`.
const ROOMS: Dictionary = {
	&"vault": preload("res://scenes/rooms/vault_room.tscn"),
	&"haven": preload("res://scenes/rooms/forge_haven.tscn"),
}

enum Boot { SKIRMISH, STORY }

@export var boot: Boot = Boot.SKIRMISH

## Seconds without a fight before fallen companions rise.
@export var calm_time: float = 3.0

## The members who have joined, in `GameState.MEMBERS` order, Álvar first: the `Party` node's.
var party: Array[Unit]:
	get:
		return _party.members
## Always `party[0]`, Álvar, whose fall ends the round.
var player: Unit:
	get:
		return _party.leader
var selected: Unit:
	get:
		return _party.selected
var enemies: Array[Unit] = []
## The room the party is in.
var room: Room
## What outlives a room. Set before entering the tree, or made at `_ready()`: the skirmish's, or a new game.
var state: GameState
## Where the story is saved; null in a skirmish. Set before entering the tree, or made at `_ready()`.
var store: SaveStore
## Whether the story opens on the title screen. Not used yet.
var show_title: bool = true
## Whether a new game opens with its first conversation. Not used yet.
var opening_enabled: bool = true

## Seconds since a fight was last on or a party member last fell.
var _calm_for: float = 0.0
var _cleared: bool = false
var _paused: bool = false
## Each member's vitals in `state` as the room was entered, for a restart.
var _entry_vitals: Dictionary = {}  # StringName member -> Vector2i

@onready var input: PlayerInput = $PlayerInput
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var _units: Node3D = $Units
@onready var _party: Party = $Party


func _enter_tree() -> void:
	# A language given on the command line (as the tests do) wins over the page and the system.
	if not _locale_chosen_before_start():
		Language.apply(Language.pick(Language.requested_from_page(), OS.get_locale()))
	var probe: Node = get_node_or_null(^"/root/Probe")
	if probe != null:
		probe.watch(self)


func _ready() -> void:
	input.select_requested.connect(select)
	input.select_next_requested.connect(select_next)
	_party.selection_changed.connect(_on_selection_changed)
	_party.member_fell.connect(_on_member_died)
	_party.member_rose.connect(_on_member_revived)
	input.targeting_changed.connect(hud.show_targeting)
	hud.member_pressed.connect(input.press_member)
	hud.gift_chosen.connect(input.press_gift)
	selection_changed.connect(hud.show_selected)
	pause_changed.connect(hud.set_paused)
	room_cleared.connect(hud.show_cleared)
	if boot == Boot.STORY and store == null:
		store = SaveStore.new()
	if state == null:
		state = GameState.new_game() if boot == Boot.STORY else GameState.skirmish()
	if not ROOMS.has(state.room):
		var fresh := GameState.new_game()
		push_warning("The game state's room %s does not exist; starting in %s" % [state.room, fresh.room])
		state.room = fresh.room
		state.entry = fresh.entry
	_enter(state.room, state.entry)


func _process(_delta: float) -> void:
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if not player.is_alive() and Input.is_action_just_pressed(&"confirm"):
		start_room()
	if Input.is_action_just_pressed(&"pause"):
		set_paused(not _paused)


func _physics_process(delta: float) -> void:
	if not _paused:
		_advance_fight_flow(delta)
	# Also while paused, so the marks are right while the player plans.
	_update_feed_marks()


## Plays the room again. In a skirmish: the vault afresh, with the whole party at full strength. In the
## story: the current room, from its entry, with the health and Blood the party had on entering it.
func start_room() -> void:
	if boot == Boot.SKIRMISH:
		state = GameState.skirmish()
	else:
		for member: StringName in _entry_vitals:
			var vitals: Vector2i = _entry_vitals[member]
			state.set_vitals(member, vitals.x, vitals.y)
	_enter(state.room, state.entry)


## Takes the party to `room_id`, arriving at its entry `entry` (or at its start, with a warning, when
## it has none), with each member's health and Blood as they leave; a fallen member arrives risen at
## `Unit.risen_health()`. An unknown room is refused with a warning.
func enter_room(room_id: StringName, entry: StringName = Room.START) -> void:
	if not ROOMS.has(room_id):
		push_warning("There is no room %s; staying in %s" % [room_id, room.room_id])
		return
	_record_vitals()
	_enter(room_id, entry)


## Freezes or releases every unit; camera, selection and orders keep working. Orders given while
## frozen are stored by the units and begin on release. Turning it on is refused while Álvar is down.
func set_paused(on: bool) -> void:
	if on == _paused or (on and not player.is_alive()):
		return
	_paused = on
	_units.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	pause_changed.emit(on)


func is_paused() -> bool:
	return _paused


## True from the fall of this round's last enemy until the next round starts.
func is_cleared() -> bool:
	return _cleared


## Gives camera and input to `unit` and sets the other living members following it.
## Ignored unless `unit` is a living party member, and while Álvar is down.
func select(unit: Unit) -> void:
	_party.select(unit)


## Selects the next living party member after the selected one, wrapping round. Ignored while Álvar is down.
func select_next() -> void:
	_party.select_next()


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


## Signals a cleared room once and raises the fallen at once; otherwise raises them after `calm_time`
## without a fight. Nothing happens while Álvar is down.
func _advance_fight_flow(delta: float) -> void:
	if not player.is_alive():
		return
	if not _cleared and enemies_alive() == 0:
		_cleared = true
		state.set_flag(_cleared_flag(room.room_id))
		room_cleared.emit()
		_party.revive_fallen()
	if fight_is_on():
		_calm_for = 0.0
		return
	_calm_for += delta
	if _calm_for >= calm_time:
		_party.revive_fallen()


## Marks exactly the living enemies the selected member can feed on, whatever its Blood; none while
## Álvar is down.
func _update_feed_marks() -> void:
	var feeder: Unit = selected if player != null and player.is_alive() else null
	for enemy: Unit in enemies:
		enemy.set_feed_mark(feeder != null and feeder.can_feed_on(enemy))


## True when the engine's locale is no longer the system's: `--language` (or code) chose it. Godot keeps
## `--language` out of `OS.get_cmdline_args()`, so the locales are compared. When they match, picking
## again gives the same language, or English where the system's has no texts.
func _locale_chosen_before_start() -> bool:
	return TranslationServer.get_locale() != TranslationServer.standardize_locale(OS.get_locale())


## Clears the last room's units, loads `room_id` and spawns the party at `entry_name` and the room's
## enemies, with Álvar selected and nothing paused or targeted.
func _enter(room_id: StringName, entry_name: StringName) -> void:
	set_paused(false)
	input.cancel_targeting()
	for unit: Node in _units.get_children():
		# Out of the tree at once, so no new unit finds an old one in the "units" group.
		_units.remove_child(unit)
		unit.queue_free()
	_party.clear()
	enemies.clear()
	_calm_for = 0.0
	_load_room(room_id)

	var entry: Marker3D = room.entry(entry_name)
	var members: Array[StringName] = state.joined()
	for index: int in members.size():
		var marker: Node3D = entry if index == 0 else entry.get_node(NodePath("Companion%d" % index))
		_party.add(_spawn_member(members[index], marker))
	hud.bind_party(party)
	hud.hide_fallen()
	hud.hide_cleared()
	# A room without enemies has nothing to clear, so it starts cleared too, and nothing is signalled.
	_cleared = state.has_flag(_cleared_flag(room_id)) or room.enemy_markers().is_empty()
	if not state.has_flag(_cleared_flag(room_id)):
		for marker: Marker3D in room.enemy_markers():
			var scene: PackedScene = SERGEANT if room.sergeant_spawns.has(StringName(marker.name)) else CRUSADER
			enemies.append(_spawn(scene, marker))

	state.room = room_id
	state.entry = StringName(String(entry.name).trim_prefix(Room.ENTRY_PREFIX))
	_entry_vitals.clear()
	for member: StringName in members:
		_entry_vitals[member] = state.vitals(member)
	input.rig = rig
	input.enabled = true
	select(player)
	rig.snap_to_target()
	room_started.emit()


## Stores each member's health and Blood in `state`; a fallen member's as `Unit.risen_health()`.
func _record_vitals() -> void:
	for member: Unit in party:
		var health: int = member.stats.health
		if not member.is_alive():
			health = Unit.risen_health(member.stats)
		state.set_vitals(member.member_id, health, member.stats.blood)


## The party member `member_id` at `marker`, with only the Gifts it knows, in its scene's order, and
## the vitals `state` holds for it.
func _spawn_member(member_id: StringName, marker: Node3D) -> Unit:
	var unit: Unit = (MEMBERS[member_id] as PackedScene).instantiate()
	var gift_user: GiftUser = unit.get_node(^"Gifts")
	var known: Array[StringName] = state.known_gifts(member_id)
	var gifts: Array[Gift] = []
	for gift: Gift in gift_user.gifts:
		if known.has(gift.id):
			gifts.append(gift)
	gift_user.gifts = gifts
	var vitals: Vector2i = state.vitals(member_id)
	if vitals.y >= 0:
		# Set as the starting Blood, so the unit begins with it and its Fury sees no fall into it.
		var stats: Stats = unit.stats.duplicate()
		stats.starting_blood = vitals.y
		unit.stats = stats
	_units.add_child(unit)
	unit.global_transform = marker.global_transform
	if vitals.x >= 0:
		var health: int = Unit.risen_health(unit.stats) if vitals.x == 0 else mini(vitals.x, unit.stats.max_health)
		unit.stats.take_damage(unit.stats.max_health - health)
	return unit


static func _cleared_flag(room_id: StringName) -> StringName:
	return StringName("%s_cleared" % room_id)


## Puts the room `room_id` in place of the current one, first among the children.
func _load_room(room_id: StringName) -> void:
	if room != null:
		# Out of the tree at once, so its navigation region leaves the map before the new one joins.
		remove_child(room)
		room.queue_free()
	room = (ROOMS[room_id] as PackedScene).instantiate()
	add_child(room)
	move_child(room, 0)
	# Owned like the rest of the scene, so `find_child` reaches its markers.
	room.owner = self


func _spawn(scene: PackedScene, marker: Node3D) -> Unit:
	var unit: Unit = scene.instantiate()
	_units.add_child(unit)
	unit.global_transform = marker.global_transform
	return unit


func _on_selection_changed(unit: Unit) -> void:
	rig.target = unit
	input.unit = unit
	_update_feed_marks()
	selection_changed.emit(unit)


## The party hands selection back to Álvar itself when a selected companion falls.
func _on_member_died(unit: Unit) -> void:
	_calm_for = 0.0
	party_changed.emit()
	if unit == player:
		input.cancel_targeting()
		input.enabled = false
		_update_feed_marks()
		hud.show_fallen()


func _on_member_revived(_unit: Unit) -> void:
	party_changed.emit()
