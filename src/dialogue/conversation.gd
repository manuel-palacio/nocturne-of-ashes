class_name Conversation
extends Node
## The conversations of `Main`: starts one through the runner when it is allowed, holds the world and
## turns player input off while it runs (which closes targeting and silences the Gift keys), and gives
## both back when it ends. Shows or hides the room's characters by the story flags and starts their
## conversations when they are used.
##
## A conversation is refused while a fight is on, while Álvar is down and while another one runs.
## It reaches the game only through a `StoryHooks` on the state of the current room.

## A conversation ran to its end; not emitted for one ended by `stop()` or by an error.
signal ended

var _runner: DialogueRunner
var _input: PlayerInput
var _party: Party
var _encounter: Encounter
## Holds the world while called with true and releases this hold with false.
var _hold: Callable
var _room: Room
var _state: GameState
## True while `stop()` ends a conversation, so that end is not reported as `ended`.
var _stopping: bool = false


## Called once by `Main`, before any room.
func setup(runner: DialogueRunner, input: PlayerInput, party: Party, encounter: Encounter,
		hold: Callable) -> void:
	_runner = runner
	_input = input
	_party = party
	_encounter = encounter
	_hold = hold
	runner.finished.connect(_on_finished)


## Starts the conversation at the cue `title` of `resource`, unless it is refused.
func talk(resource: Resource, title: String) -> void:
	if not can_talk():
		return
	_input.enabled = false
	# Held at the end of the frame: a unit using someone asks for the talk in the middle of its
	# physics step, and a held unit leaves the physics space.
	_hold_while_talking.call_deferred()
	_runner.start(resource, title, StoryHooks.new(_state, func() -> Unit: return _party.leader))


## Whether a conversation may start now: a room is entered, no fight is on, Álvar is up and no one
## is talking.
func can_talk() -> bool:
	return (not _runner.is_running() and _state != null and not _encounter.fight_is_on()
			and _leader_alive())


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


func _hold_while_talking() -> void:
	_hold.call(_runner.is_running())


func _leader_alive() -> bool:
	return _party.leader != null and _party.leader.is_alive()


func _on_room_child_entered(child: Node) -> void:
	if child is Npc:
		_take(child)


func _on_flag_changed(_key: StringName) -> void:
	_show_characters()


func _on_talk_requested(npc: Npc, _by: Unit) -> void:
	talk(npc.dialogue, npc.title)


func _on_finished() -> void:
	_hold.call(false)
	_input.enabled = true
	if not _stopping and not _runner.ended_in_error():
		ended.emit()
