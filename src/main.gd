class_name Main
extends Node3D
## The game's shell: boots from a `GameState`, loads rooms, has the `Party` spawn the members who have
## joined and the `Encounter` run the room's fight, wires camera, input and HUD, hands control to the
## party's selected member, pauses the world, has the `Conversation` node run conversations, the
## `Hints` node teach the fight's rules as they first apply and, in a story, the `Travel` node answer
## the doors.
##
## The skirmish (`main.tscn`) always plays the vault with the whole party at full strength and restarts
## it after Álvar's fall. The story (`game.tscn`) plays from a `GameState`, saves it at checkpoints and
## reloads the last checkpoint after Álvar's fall; it opens on the title, with Continue and New game.
## Where the story rests for now, the room `STORY_REST_ROOM` once cleared, the HUD's closing card says
## so, once, holding the world as the controls card does; it waits for the pause, a conversation and
## the controls card to close first.
##
## When the page is hidden (on the web: the document's `visibilitychange`; elsewhere: the window losing
## focus) the world pauses as Space pauses it, unless a conversation, a card, the fall prompt or the
## title is showing; it is never resumed by itself.

## Emitted whenever a room is entered (also on a reload and a new game), once its units are in place.
signal room_started
## Emitted when a party member becomes the selected one, as `Party.selection_changed` describes.
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

## Where the story rests for now: once this room is cleared, the closing card says so.
const STORY_REST_ROOM: StringName = &"vault"
## Set when the closing card is dismissed, so it is shown once; saved with the state.
const REST_SHOWN_FLAG: StringName = &"rest_shown"
## Shown on entering the cleared `STORY_REST_ROOM` once the closing card has been seen.
const REST_NOTICE: String = "The vault is quiet. The story rests here, for now."
## Shown on coming back to a room left with its fight begun and enemies standing: they are restored.
const REGROUPED_NOTICE: String = "The vault's guard has closed ranks again."
## Shown on coming back to a room after a fall, once falls have tired its guard (`guard_health()`).
const TIRING_NOTICE: String = "The guard is tiring."
## Shown on coming back through a door to a room whose guard falls have tired, in place of
## `REGROUPED_NOTICE` and `TIRING_NOTICE`: the guard is whole again, as the door hint said, but tired.
const TIRED_REGROUPED_NOTICE: String = "The guard has closed ranks, and tires."
## Seconds `TIRING_NOTICE` and `TIRED_REGROUPED_NOTICE` stay on show: long enough to be read after the fall prompt.
const TIRING_NOTICE_TIME: float = 4.0
## From this fall of Álvar's in the same room on, its guard comes back tired.
const TIRING_FROM_FALL: int = 2
## Each such fall takes this share of the guard's tuned health, down to `TIRING_FLOOR`.
const TIRING_STEP: float = 0.15
const TIRING_FLOOR: float = 0.15

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
## so anything that listens to it must read `main.state` again on `room_started`, as the `Conversation`
## node does for `GameState.flag_changed`.
var state: GameState
## Where the story is saved; null in a skirmish. Set before entering the tree, or made at `_ready()`.
var store: SaveStore
## Whether the story opens on the title screen. Set before entering the tree. While the title is open
## there is no room and no party, the world is held and input is off.
var show_title: bool = true
## Whether a new game opens with its first conversation, as `Conversation.play_opening()` describes.
var opening_enabled: bool = true

var _paused: bool = false
## The state at the last checkpoint, as `GameState.to_dict()`, for a reload when the store has none.
var _last_checkpoint: Dictionary = {}
## Whether the closing card is due, waiting for the pause, a conversation or the controls card to end.
var _closing_due: bool = false
## Whether the last checkpoint could not be written, so the closing card does not say the game is saved.
var _last_write_failed: bool = false
## True while the closing card is closed by a room change rather than by the player.
var _closing_put_away: bool = false
## Held so the page's `visibilitychange` callback stays alive; on the web only.
var _visibility_callback: JavaScriptObject
## The rooms left in this play through a door with their fight begun (an enemy hurt or fallen) and
## enemies standing, whose enemies are whole again on the way back. Forgotten on a reload or a new game.
var _left_mid_fight: Dictionary = {}  # StringName -> true
## Álvar's falls in each room since it was last cleared or a game begun, by `Room.room_id`. Kept in this
## play only, outside the state: a fall's reload of the checkpoint and leaving by a door keep it,
## nothing saves it, so a page reload forgets it.
var _falls: Dictionary = {}  # StringName -> int

@onready var input: PlayerInput = $PlayerInput
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
## Runs the conversations; driven through `talk()`.
@onready var dialogue: DialogueRunner = $DialogueRunner
@onready var _units: Node3D = $Units
@onready var _party: Party = $Party
@onready var _encounter: Encounter = $Encounter
@onready var _conversation: Conversation = $Conversation
@onready var _world_hold: WorldHold = $WorldHold
@onready var _travel: Travel = $Travel
@onready var _hints: Hints = $Hints
@onready var _warmup: ShaderWarmup = $ShaderWarmup
## Only the story scene has one.
@onready var _title: TitleScreen = get_node_or_null(^"TitleLayer/TitleScreen")


func _enter_tree() -> void:
	PageBoot.configure(self)
	# A language given on the command line (as the tests do) wins over the page and the system.
	if not _locale_chosen_before_start():
		Language.apply(Language.pick(Language.requested_from_page(), OS.get_locale()))
	var probe: Node = get_node_or_null(^"/root/Probe")
	if probe != null:
		probe.watch(self)


func _ready() -> void:
	_world_hold.setup(_units, _encounter)
	# First, so the feed marks are right before anyone else hears of a fall or a selection.
	_encounter.watch(_party)
	_encounter.cleared.connect(room_cleared.emit)
	input.select_requested.connect(select)
	input.select_next_requested.connect(select_next)
	_party.selection_changed.connect(_on_selection_changed)
	_party.member_fell.connect(_on_member_died)
	_party.member_rose.connect(_on_member_revived)
	_party.member_added.connect(_on_member_added)
	_party.gifts_changed.connect(_on_gifts_changed)
	input.targeting_changed.connect(hud.show_targeting)
	input.notice_requested.connect(hud.show_notice)
	hud.member_pressed.connect(input.press_member)
	hud.gift_chosen.connect(input.press_gift)
	hud.fallen_pressed.connect(reload_checkpoint)
	hud.controls_toggled.connect(_on_controls_toggled)
	hud.closing_toggled.connect(_on_closing_toggled)
	selection_changed.connect(hud.show_selected)
	pause_changed.connect(hud.set_paused)
	room_cleared.connect(hud.show_cleared)
	# A cleared room stays cleared even if Álvar falls right after.
	room_cleared.connect(checkpoint)
	room_cleared.connect(_on_room_cleared)
	_conversation.setup(dialogue, input, _party, _encounter, _world_hold)
	hud.bind_dialogue(dialogue)
	# An ended conversation is a checkpoint, a stopped one is not, a failed one reloads the last (deferred).
	_conversation.ended.connect(checkpoint)
	_conversation.failed.connect(reload_checkpoint, CONNECT_DEFERRED)
	room_started.connect(func() -> void: _conversation.play_opening(opening_enabled))
	_travel.setup(input, _party, _encounter, hud, enter_room)
	_hints.setup(_party, _encounter, hud, func() -> bool:
		return (is_title_open() or is_talking() or hud.is_controls_open() or hud.is_closing_open()
				or hud.is_fallen_shown()), keep_flag)
	if boot == Boot.STORY and store == null:
		store = SaveStore.new()
	if state == null:
		state = GameState.new_game() if boot == Boot.STORY else GameState.skirmish()
	input.rig = rig
	_watch_page_visibility()
	if boot == Boot.STORY and show_title and _title != null:
		_open_title()
	else:
		_play(state)


func _process(_delta: float) -> void:
	if _closing_due:
		_open_closing_when_free()
	# While talking, the dialogue box has the keys; while a card is open, the card has them.
	if is_title_open() or is_talking() or hud.is_controls_open() or hud.is_closing_open():
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if not player.is_alive() and hud.is_fallen_answerable() and Input.is_action_just_pressed(&"confirm"):
		reload_checkpoint()
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
## `Unit.risen_health()`, and in a room without living enemies everyone's health is full. An unknown
## room is refused with a warning.
## It removes physics bodies from the tree at once, so from a physics callback such as `body_entered`
## call it deferred.
func enter_room(room_id: StringName, entry: StringName = Room.START) -> void:
	if not ROOMS.has(room_id):
		push_warning("There is no room %s; staying in %s" % [room_id, room.room_id])
		return
	_party.record(state)
	if room != null and not _encounter.is_cleared() and _encounter.is_disturbed():
		_left_mid_fight[room.room_id] = true
	_enter(room_id, entry, true)
	checkpoint()


## Records the party's health and Blood in `state`, keeps it in memory and saves it. Does nothing in a
## skirmish, while the title is open, or before a room is entered.
func checkpoint() -> void:
	if store == null or room == null or is_title_open():
		return
	_party.record(state)
	_last_checkpoint = state.to_dict()
	_last_write_failed = not store.save(state)
	if _last_write_failed:
		push_warning("Could not write the save file %s" % store.path)
		return
	checkpoint_saved.emit()


## Sets `flag` in the state and in the last checkpoint, and saves that checkpoint: a flag set mid-room
## that neither a fall nor a reload may undo, such as a hint seen. Nothing else in the checkpoint
## changes, the party's health and Blood included. Without a store or a checkpoint, only the state.
func keep_flag(flag: StringName) -> void:
	state.set_flag(flag)
	if store == null or _last_checkpoint.is_empty():
		return
	var kept: GameState = GameState.from_dict(_last_checkpoint)
	kept.set_flag(flag)
	_last_checkpoint = kept.to_dict()
	_last_write_failed = not store.save(kept)
	if _last_write_failed:
		push_warning("Could not write the save file %s" % store.path)


## Plays on from the last checkpoint kept in memory, at its room and entry: within a session it is
## never older than the file, which a failed write leaves behind. Without one (at boot), from the
## store's save, else from a new game. In a skirmish, with no save, it restarts the room.
func reload_checkpoint() -> void:
	if store == null:
		start_room()
		return
	var saved: GameState = (GameState.from_dict(_last_checkpoint) if not _last_checkpoint.is_empty()
			else store.load_state())
	_play(saved if saved != null else GameState.new_game())


## Forgets the save and the last checkpoint and starts a new game in the haven.
func new_game() -> void:
	if store != null:
		store.clear()
	_last_checkpoint = {}
	_falls.clear()
	_play(GameState.new_game())


## Freezes or releases every unit; camera, selection and orders keep working. Orders given while
## frozen are stored by the units and begin on release. Turning it on is refused while Álvar is down.
func set_paused(on: bool) -> void:
	if on == _paused or (on and (player == null or not player.is_alive())):
		return
	_paused = on
	_world_hold.set_held(&"pause", on)
	pause_changed.emit(on)


func is_paused() -> bool:
	return _paused


## The page was hidden, or the window lost focus: pauses as Space does, unless a conversation, the
## controls or closing card, the fall prompt or the title is showing, or there is no room yet.
func page_hidden() -> void:
	if room == null or is_title_open() or is_talking() or hud.is_controls_open() or hud.is_closing_open():
		return
	set_paused(true)


## Starts a conversation at the cue `title` of `resource`, as `Conversation.talk()` describes.
func talk(resource: Resource, title: String) -> void:
	_conversation.talk(resource, title)


func is_talking() -> bool:
	return _conversation.is_talking()


func is_title_open() -> bool:
	return _title != null and _title.is_open()


## Whether the closing card, saying the story rests here, is open.
func is_closing_open() -> bool:
	return hud.is_closing_open()


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


## The share of its tuned health the guard of the current room comes back with after Álvar's falls
## there: whole for the first `TIRING_FROM_FALL` − 1 falls, then `TIRING_STEP` of it less for each,
## never below `TIRING_FLOOR`.
func guard_health() -> float:
	var falls: int = _falls.get(room.room_id, 0) if room != null else 0
	if falls < TIRING_FROM_FALL:
		return 1.0
	return maxf(1.0 - TIRING_STEP * (falls - TIRING_FROM_FALL + 1), TIRING_FLOOR)


## Off the web, the window losing focus hides the game. On the web the engine sends no application
## focus-out (only the window's, when its canvas loses focus) and nothing when the page is hidden, so
## the page's visibility is followed instead.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not OS.has_feature("web"):
		page_hidden()


func _exit_tree() -> void:
	if _visibility_callback != null:
		JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", _visibility_callback)
		_visibility_callback = null


## On the web, follows the document's `visibilitychange`: a page becoming hidden is `page_hidden()`.
func _watch_page_visibility() -> void:
	if not OS.has_feature("web"):
		return
	_visibility_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
	JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility_callback)


func _on_visibility_changed(_args: Array) -> void:
	if JavaScriptBridge.eval("document.hidden", true):
		page_hidden()


## True when the engine's locale is no longer the system's: `--language` (or code) chose it. Godot keeps
## `--language` out of `OS.get_cmdline_args()`, so the locales are compared. When they match, picking
## again gives the same language, or English where the system's has no texts.
func _locale_chosen_before_start() -> bool:
	return TranslationServer.get_locale() != TranslationServer.standardize_locale(OS.get_locale())


## Makes `from` the state and enters its room at its entry, or a new game's room and entry, with a
## warning, when its room does not exist; then saves. Closes the title first.
func _play(from: GameState) -> void:
	_warmup.stop()
	if is_title_open():
		_title.close()
		_world_hold.set_held(&"title", false)
	state = from
	_left_mid_fight.clear()
	if not ROOMS.has(state.room):
		var fresh := GameState.new_game()
		push_warning("The game state's room %s does not exist; starting in %s" % [state.room, fresh.room])
		state.room = fresh.room
		state.entry = fresh.entry
	_enter(state.room, state.entry)
	checkpoint()


## Stops any conversation, clears the last room's units, loads `room_id`, spawns the party at
## `entry_name`, rested when the room has no living enemies, and starts the room's fight and
## characters, with Álvar selected and nothing paused or targeted. `through_door`: the party came by
## `enter_room()`, not by a reload or a restart, which picks the tired guard's line.
func _enter(room_id: StringName, entry_name: StringName, through_door: bool = false) -> void:
	_conversation.stop()
	_put_closing_away()
	set_paused(false)
	input.cancel_targeting()
	_clear_units()
	_load_room(room_id)
	var arrived_at: StringName = _spawn_party(entry_name)
	_encounter.guard_health = guard_health()
	_encounter.begin(room, state, _units)
	_party.arrive(_encounter.is_cleared())
	_conversation.begin_room(room, state)
	if boot == Boot.STORY:
		_travel.begin_room(room, state)
	_hints.begin_room(state, boot == Boot.STORY)
	hud.bind_state(state if boot == Boot.STORY else null)
	state.room = room_id
	state.entry = arrived_at
	_party.remember_entry_vitals(state)
	rig.far_fraction = room.camera_far_fraction
	rig.set_bounds(room.floor_bounds())
	_hand_control_to_alvar()
	var regrouped: bool = _left_mid_fight.has(room_id)
	_left_mid_fight.erase(room_id)
	if not _encounter.is_cleared():
		if guard_health() < 1.0 and through_door:
			hud.show_notice(TIRED_REGROUPED_NOTICE, [], TIRING_NOTICE_TIME)
		elif guard_health() < 1.0:
			hud.show_notice(TIRING_NOTICE, [], TIRING_NOTICE_TIME)
		elif regrouped:
			hud.show_notice(REGROUPED_NOTICE)
	if _is_story_rest():
		if state.has_flag(REST_SHOWN_FLAG):
			hud.show_notice(REST_NOTICE)
		else:
			_closing_due = true
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
	_party.begin_room(state, room, entry, _units)
	hud.bind_party(party)
	if entry == null:
		return Room.START
	return StringName(String(entry.name).trim_prefix(Room.ENTRY_PREFIX))


## Shows the title, offering Continue when there is a usable save, and a line when saves will not
## keep, and holds the world until a choice.
## Called once, at boot.
func _open_title() -> void:
	_title.continue_chosen.connect(reload_checkpoint)
	_title.new_game_chosen.connect(new_game)
	_world_hold.set_held(&"title", true)
	input.enabled = false
	_title.open(store.has_save())
	_title.show_storage_warning(not store.keeps_saves())
	# Behind the title, the rooms' shaders are compiled while the player reads it, a little a frame.
	_title.show_preparing(true)
	_warmup.ended.connect(_title.show_preparing.bind(false), CONNECT_ONE_SHOT)
	_warmup.stepped.connect(_title.show_preparing_step)
	_warmup.start([ROOMS[&"haven"], ROOMS[&"vault"]])


func _hand_control_to_alvar() -> void:
	hud.hide_fallen()
	hud.hide_cleared()
	hud.hide_notice()
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
	_world_hold.set_air(room.air())


func _on_selection_changed(unit: Unit) -> void:
	rig.target = unit
	input.unit = unit
	input.leader = player
	selection_changed.emit(unit)


## The party hands selection back to Álvar itself when a selected companion falls.
func _on_member_died(unit: Unit) -> void:
	party_changed.emit()
	if unit == player:
		_count_fall()
		input.cancel_targeting()
		input.enabled = false
		hud.show_fallen()


## The controls card holds the world as the pause does, the room's air with it, and while it is open
## no key or click reaches the game. Input comes back at the end of the frame the card closes in, so
## the Escape that closed it does not also cancel a Gift's targeting.
func _on_controls_toggled(open: bool) -> void:
	_world_hold.set_held(&"controls", open)
	if open:
		input.suspended = true
	else:
		input.set_deferred(&"suspended", false)


## Whether this is the story, in its resting room, cleared: where the story rests for now.
func _is_story_rest() -> bool:
	return (boot == Boot.STORY and room != null and room.room_id == STORY_REST_ROOM
			and _encounter.is_cleared())


func _on_room_cleared() -> void:
	_falls.erase(room.room_id)
	if _is_story_rest():
		_closing_due = true
		_open_closing_when_free()


## Opens the closing card once nothing else holds the screen: not on the title, in a conversation, over
## the controls card, in the pause or after Álvar's fall. It says the game is saved only when the cleared
## vault's checkpoint was written and the store keeps saves.
func _open_closing_when_free() -> void:
	if (is_title_open() or is_talking() or hud.is_controls_open() or _paused or player == null
			or not player.is_alive()):
		return
	_closing_due = false
	hud.show_closing(state.conscience, store != null and not _last_write_failed and store.keeps_saves())


## Closes the closing card without counting it as seen, as a room change does; nothing is due after.
func _put_closing_away() -> void:
	_closing_due = false
	if not hud.is_closing_open():
		return
	_closing_put_away = true
	hud.hide_closing()
	_closing_put_away = false


## The closing card holds the world and the input as the controls card does. Dismissed by the player,
## it is seen: the flag is set and saved, so it does not show again, and the line shown on coming back
## to the quiet vault is shown at once, so a line stays on screen after the card.
func _on_closing_toggled(open: bool) -> void:
	_world_hold.set_held(&"closing", open)
	if open:
		input.suspended = true
		return
	input.set_deferred(&"suspended", false)
	if not _closing_put_away:
		state.set_flag(REST_SHOWN_FLAG)
		checkpoint()
		hud.show_notice(REST_NOTICE)


func _on_member_revived(_unit: Unit) -> void:
	party_changed.emit()


## A member who joined mid-room gets a panel; the selection stays as it was. Targeting closes, as the
## HUD's rebuilt Gift bar no longer marks it.
func _on_member_added(_unit: Unit) -> void:
	input.cancel_targeting()
	hud.bind_party(party)
	if selected != null:
		hud.show_selected(selected)


## The Gift bar shows the selected member's Gifts as they now are; targeting closes, as indices move.
func _on_gifts_changed(unit: Unit) -> void:
	if unit == selected:
		input.cancel_targeting()
		hud.show_selected(unit)


## Counts a fall of Álvar's in the current room.
func _count_fall() -> void:
	if room != null:
		_falls[room.room_id] = _falls.get(room.room_id, 0) + 1
