class_name Main
extends Node3D
## The game's shell: boots from a `GameState`, loads rooms, has the `Party` spawn the members who have
## joined and the `Encounter` run the room's fight, wires camera, input and HUD, hands control to the
## party's selected member, and pauses the world.
##
## The skirmish (`main.tscn`) always plays the vault with the whole party at full strength and restarts
## it after Álvar's fall. The story (`game.tscn`) plays from a `GameState`, saves it at checkpoints and
## reloads the last checkpoint after Álvar's fall; it opens on the title, with Continue and New game.

## Emitted whenever a room is entered (also on a reload and a new game), once its units are in place.
signal room_started
## Emitted when a living party member becomes the selected one.
signal selection_changed(unit: Unit)
## Emitted once per round, when the last enemy falls; not when a room is entered already cleared.
signal room_cleared
## Emitted when a party member falls or rises.
signal party_changed
## Emitted when the world pause turns on or off.
signal pause_changed(paused: bool)
## Emitted when `checkpoint()` has saved the state.
signal checkpoint_saved

## Every room, by its `Room.room_id`.
const ROOMS: Dictionary = {
	&"vault": preload("res://scenes/rooms/vault_room.tscn"),
	&"haven": preload("res://scenes/rooms/forge_haven.tscn"),
}

enum Boot { SKIRMISH, STORY }

@export var boot: Boot = Boot.SKIRMISH

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
## The room's enemies: the `Encounter` node's.
var enemies: Array[Unit]:
	get:
		return _encounter.enemies
## Seconds without a fight before fallen companions rise: the `Encounter` node's.
var calm_time: float:
	get:
		return _encounter.calm_time
	set(value):
		_encounter.calm_time = value
## The room the party is in.
var room: Room
## What outlives a room. Set before entering the tree, or made at `_ready()`: the skirmish's, or a new game.
## The skirmish's `start_room()`, `reload_checkpoint()` and `new_game()` replace it with another object,
## so anything that listens to it must read `main.state` again on `room_started`.
var state: GameState
## Where the story is saved; null in a skirmish. Set before entering the tree, or made at `_ready()`.
var store: SaveStore
## Whether the story opens on the title screen. Set before entering the tree. While the title is open
## there is no room and no party, the world is held and input is off.
var show_title: bool = true
## Whether a new game opens with its first conversation. Not used yet.
var opening_enabled: bool = true

var _paused: bool = false

@onready var input: PlayerInput = $PlayerInput
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var _units: Node3D = $Units
@onready var _party: Party = $Party
@onready var _encounter: Encounter = $Encounter
## Only the story scene has one.
@onready var _title: TitleScreen = get_node_or_null(^"TitleLayer/TitleScreen")


func _enter_tree() -> void:
	# A language given on the command line (as the tests do) wins over the page and the system.
	if not _locale_chosen_before_start():
		Language.apply(Language.pick(Language.requested_from_page(), OS.get_locale()))
	var probe: Node = get_node_or_null(^"/root/Probe")
	if probe != null:
		probe.watch(self)


func _ready() -> void:
	# First, so the feed marks are right before anyone else hears of a fall or a selection.
	_encounter.watch(_party)
	_encounter.cleared.connect(room_cleared.emit)
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
	# A cleared room stays cleared even if Álvar falls right after.
	room_cleared.connect(checkpoint)
	if boot == Boot.STORY and store == null:
		store = SaveStore.new()
	if state == null:
		state = GameState.new_game() if boot == Boot.STORY else GameState.skirmish()
	input.rig = rig
	if _title != null:
		_title.continue_chosen.connect(reload_checkpoint)
		_title.new_game_chosen.connect(new_game)
	if boot == Boot.STORY and show_title and _title != null:
		_open_title()
	else:
		_play(state)


func _process(_delta: float) -> void:
	if _title_is_open():
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if not player.is_alive() and Input.is_action_just_pressed(&"confirm"):
		if store != null:
			reload_checkpoint()
		else:
			start_room()
	if Input.is_action_just_pressed(&"pause"):
		set_paused(not _paused)


## Plays the room again. In a skirmish: the vault afresh, with the whole party at full strength. In the
## story: the current room, from its entry, with the health and Blood the party had on entering it, and
## nothing else rolled back; after a fall the story reloads its checkpoint instead.
func start_room() -> void:
	if boot == Boot.SKIRMISH:
		state = GameState.skirmish()
	else:
		_party.restore_entry_vitals(state)
	_enter(state.room, state.entry)


## Takes the party to `room_id`, arriving at its entry `entry` (or at its start, with a warning, when
## it has none), with each member's health and Blood as they leave; a fallen member arrives risen at
## `Unit.risen_health()`. An unknown room is refused with a warning.
## It removes physics bodies from the tree at once, so from a physics callback such as `body_entered`
## call it deferred.
func enter_room(room_id: StringName, entry: StringName = Room.START) -> void:
	if not ROOMS.has(room_id):
		push_warning("There is no room %s; staying in %s" % [room_id, room.room_id])
		return
	_party.record(state)
	_enter(room_id, entry)
	checkpoint()


## Records the party's health and Blood in `state` and saves it. Does nothing in a skirmish.
func checkpoint() -> void:
	if store == null:
		return
	_party.record(state)
	if not store.save(state):
		push_warning("Could not write the save file %s" % store.path)
		return
	checkpoint_saved.emit()


## Plays on from the saved state, or from a new game when there is no usable save: its room, at its
## entry. In a skirmish, with no save, it restarts the room.
func reload_checkpoint() -> void:
	if store == null:
		start_room()
		return
	var saved: GameState = store.load_state()
	_play(saved if saved != null else GameState.new_game())


## Forgets the save and starts a new game in the haven.
func new_game() -> void:
	if store != null:
		store.clear()
	_play(GameState.new_game())


## Freezes or releases every unit; camera, selection and orders keep working. Orders given while
## frozen are stored by the units and begin on release. Turning it on is refused while Álvar is down.
func set_paused(on: bool) -> void:
	if on == _paused or (on and (player == null or not player.is_alive())):
		return
	_paused = on
	_units.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	_encounter.paused = on
	pause_changed.emit(on)


func is_paused() -> bool:
	return _paused


## True from the fall of the room's last enemy, or from entering a cleared room, until the next round.
func is_cleared() -> bool:
	return _encounter.is_cleared()


## Gives camera and input to `unit` and sets the other living members following it.
## Ignored unless `unit` is a living party member, and while Álvar is down.
func select(unit: Unit) -> void:
	_party.select(unit)


## Selects the next living party member after the selected one, wrapping round. Ignored while Álvar is down.
func select_next() -> void:
	_party.select_next()


## True while any living enemy is attacking someone.
func fight_is_on() -> bool:
	return _encounter.fight_is_on()


func enemies_alive() -> int:
	return _encounter.enemies_alive()


## True when the engine's locale is no longer the system's: `--language` (or code) chose it. Godot keeps
## `--language` out of `OS.get_cmdline_args()`, so the locales are compared. When they match, picking
## again gives the same language, or English where the system's has no texts.
func _locale_chosen_before_start() -> bool:
	return TranslationServer.get_locale() != TranslationServer.standardize_locale(OS.get_locale())


## Makes `from` the state and enters its room at its entry, or a new game's room and entry, with a
## warning, when its room does not exist; then saves. Closes the title first.
func _play(from: GameState) -> void:
	if _title_is_open():
		_title.close()
		_units.process_mode = Node.PROCESS_MODE_INHERIT
	state = from
	if not ROOMS.has(state.room):
		var fresh := GameState.new_game()
		push_warning("The game state's room %s does not exist; starting in %s" % [state.room, fresh.room])
		state.room = fresh.room
		state.entry = fresh.entry
	_enter(state.room, state.entry)
	checkpoint()


## Clears the last room's units, loads `room_id`, spawns the party at `entry_name` and starts the room's
## fight, with Álvar selected and nothing paused or targeted.
func _enter(room_id: StringName, entry_name: StringName) -> void:
	set_paused(false)
	input.cancel_targeting()
	_clear_units()
	_load_room(room_id)
	var arrived_at: StringName = _spawn_party(entry_name)
	_encounter.begin(room, state, _units)
	state.room = room_id
	state.entry = arrived_at
	_party.remember_entry_vitals(state)
	_hand_control_to_alvar()
	room_started.emit()


func _clear_units() -> void:
	for unit: Node in _units.get_children():
		# Out of the tree at once, so no new unit finds an old one in the "units" group.
		_units.remove_child(unit)
		unit.queue_free()
	_party.clear()


## Spawns the members who have joined at the room's entry `entry_name` and shows them in the HUD.
## Returns the name of the entry they arrived at. Álvar is spawned, with an error, if `state` lacks him.
func _spawn_party(entry_name: StringName) -> StringName:
	var entry: Marker3D = room.entry(entry_name)
	var members: Array[StringName] = state.joined()
	if not members.has(GameState.LEADER):
		push_error("The game state's party has no %s; spawning him anyway" % GameState.LEADER)
		members.push_front(GameState.LEADER)
	for index: int in members.size():
		var marker: Node3D = room
		if entry != null:
			marker = entry if index == 0 else room.companion_marker(entry, index)
		_party.spawn(members[index], marker, state, _units)
	hud.bind_party(party)
	if entry == null:
		return Room.START
	return StringName(String(entry.name).trim_prefix(Room.ENTRY_PREFIX))


## Shows the title, offering Continue when there is a usable save, and holds the world until a choice.
func _open_title() -> void:
	_units.process_mode = Node.PROCESS_MODE_DISABLED
	input.enabled = false
	_title.open(store.has_save())


func _title_is_open() -> bool:
	return _title != null and _title.is_open()


func _hand_control_to_alvar() -> void:
	hud.hide_fallen()
	hud.hide_cleared()
	input.enabled = true
	select(player)
	rig.snap_to_target()


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


func _on_selection_changed(unit: Unit) -> void:
	rig.target = unit
	input.unit = unit
	selection_changed.emit(unit)


## The party hands selection back to Álvar itself when a selected companion falls.
func _on_member_died(unit: Unit) -> void:
	party_changed.emit()
	if unit == player:
		input.cancel_targeting()
		input.enabled = false
		hud.show_fallen()


func _on_member_revived(_unit: Unit) -> void:
	party_changed.emit()
