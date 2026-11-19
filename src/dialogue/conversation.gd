class_name Conversation
extends Node
## The conversations of `Main`: starts one through the runner when it is allowed, holds the world and
## turns player input off while it runs (which closes targeting and silences the Gift keys), and gives
## both back when it ends. Shows or hides the room's characters by the story flags, starts their
## conversations when they are used and tells them when the line on show is theirs.
##
## A conversation is refused while a fight is on, while Álvar is down and while another one runs.
## It reaches the game only through a `StoryHooks` on the state of the current room.

## A conversation ran to its end; not emitted for one ended by `stop()` or by an error.
signal ended
## A conversation ended in an error: what it already changed should be undone.
signal failed

## The conversation a new game opens on, at the cue `OPENING_CUE`, in the room `OPENING_ROOM`, until
## the story flag `OPENING_DONE` is set.
const OPENING: Resource = preload("res://dialogue/haven.dialogue")
const OPENING_CUE: String = "waking"
const OPENING_ROOM: StringName = &"haven"
const OPENING_DONE: StringName = &"met_malakor"

var _runner: DialogueRunner
var _input: PlayerInput
var _party: Party
var _encounter: Encounter
var _world_hold: WorldHold
var _room: Room
var _state: GameState
## True while `stop()` ends a conversation, so that end is not reported as `ended`.
var _stopping: bool = false


## Called once by `Main`, before any room.
func setup(runner: DialogueRunner, input: PlayerInput, party: Party, encounter: Encounter,
		world_hold: WorldHold) -> void:
	_runner = runner
	_input = input
	_party = party
	_encounter = encounter
	_world_hold = world_hold
	runner.finished.connect(_on_finished)
	runner.line_shown.connect(_on_line_shown)


## Starts the conversation at the cue `title` of `resource`, unless it is refused.
func talk(resource: Resource, title: String) -> void:
	if not can_talk():
		return
	_input.enabled = false
	# Held at once, even from the physics step of the unit using someone: held units stay in the
	# physics space. Held before the start, so a conversation that ends at once releases it.
	_world_hold.set_held(WorldHold.TALK, true)
	_runner.start(resource, title, StoryHooks.new(_state, func() -> Unit: return _party.leader))


## Starts the opening conversation when `enabled`, the room just started is `OPENING_ROOM` and
## `OPENING_DONE` is not set. Called once a room has started and the party is in place.
func play_opening(enabled: bool) -> void:
	if (enabled and is_instance_valid(_room) and _room.room_id == OPENING_ROOM
			and not _state.has_flag(OPENING_DONE)):
		talk(OPENING, OPENING_CUE)


## Whether a conversation may start now: a room is entered, no fight is on, Álvar is up and no one
## is talking.
func can_talk() -> bool:
	return (not _runner.is_running() and _state != null and not _encounter.fight_is_on()
			and _party.leader_alive())


func is_talking() -> bool:
	return _runner.is_running()


## Ends a running conversation where it is, without `ended`: nothing further in it runs.
func stop() -> void:
	_stopping = true
	_runner.stop()
	_stopping = false


## Takes over the characters of `room`, just entered, and of any added to it later, with `state`,
## the state `Main` now holds: shows or hides them by its flags now and whenever a flag changes, and
## has them start their conversations when used, a use counting only when the talk may start. Called
## at each room start, as `Main` may hold a new state object then.
func begin_room(room: Room, state: GameState) -> void:
	if _state != null and _state.flag_changed.is_connected(_on_flag_changed):
		_state.flag_changed.disconnect(_on_flag_changed)
	_room = room
	_state = state
	_state.flag_changed.connect(_on_flag_changed)
	room.child_entered_tree.connect(_on_room_child_entered)
	for npc: Npc in room.npcs():
		_take(npc)


func _take(npc: Npc) -> void:
	npc.talk_allowed = can_talk
	npc.talk_requested.connect(_on_talk_requested)
	npc.show_by(_state)


func _show_characters() -> void:
	if not is_instance_valid(_room):
		return
	for npc: Npc in _room.npcs():
		npc.show_by(_state)


func _on_room_child_entered(child: Node) -> void:
	if child is Npc:
		_take(child)


## A flag can show or hide someone, or change what can be used: the use ring is chosen again too.
func _on_flag_changed(_key: StringName) -> void:
	_show_characters()
	_input.refresh_use_marks()


func _on_talk_requested(npc: Npc, _by: Unit) -> void:
	talk(npc.dialogue, npc.title)


## Tells each character of the room whether `speaker`, a line's speaker as written, is them.
func _show_speaker(speaker: String) -> void:
	if not is_instance_valid(_room):
		return
	for npc: Npc in _room.npcs():
		npc.set_speaking(not speaker.is_empty() and npc.label == speaker)


func _on_line_shown(speaker: String, _text: String, _choices: Array[String]) -> void:
	_show_speaker(speaker)


func _on_finished() -> void:
	_show_speaker("")
	_world_hold.set_held(WorldHold.TALK, false)
	_input.enabled = true
	if _runner.ended_in_error():
		failed.emit()
	elif not _stopping:
		ended.emit()
