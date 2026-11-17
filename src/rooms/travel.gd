class_name Travel
extends Node
## The doors of `Main`'s rooms in a story: takes the doors of each room entered and answers their uses.
## A use while a fight is on, while Álvar is in the Fury or while a member feeds or walks to a feed
## shows a notice; a use of a barred door shows its `Door.locked_text`; any other use takes the whole
## party through, wherever its members stand.
##
## Doors are used from a unit's physics step, and changing room removes every unit and the room at once,
## so the party goes through at the end of the frame, if it still may then. No door is used while player
## input is off (in a conversation, on the title, after Álvar's fall), nor in a room not begun here.

const FIGHT_TEXT: String = "Not while they are upon you"

var _input: PlayerInput
var _party: Party
var _encounter: Encounter
var _hud: Hud
## Takes the party to a room: called with the room and the entry, as `Main.enter_room()`.
var _go: Callable
var _state: GameState


## Called once by `Main`, before any room.
func setup(input: PlayerInput, party: Party, encounter: Encounter, hud: Hud, go: Callable) -> void:
	_input = input
	_party = party
	_encounter = encounter
	_hud = hud
	_go = go


## Takes over the doors of `room`, just entered, with `state`, the state `Main` now holds. Called at
## each room start of a story, as `Main` may hold a new state object then.
func begin_room(room: Room, state: GameState) -> void:
	_state = state
	for door: Node in room.find_children("*", "Door", true, false):
		_take(door as Door)


## Whether doors may be used now: input is on and Álvar is up.
func doors_usable() -> bool:
	return _state != null and _input.enabled and _party.leader_alive()


func _take(door: Door) -> void:
	door.use_allowed = doors_usable
	door.travel_requested.connect(_on_travel_requested)
	door.refused.connect(_hud.show_notice)


## The notice for going through `door` now, or empty when the party may go.
func _refusal(door: Door) -> String:
	if _encounter.fight_is_on() or _party.is_busy():
		return FIGHT_TEXT
	if door.is_locked(_state):
		return door.locked_text
	return ""


func _on_travel_requested(door: Door) -> void:
	var refusal: String = _refusal(door)
	if not refusal.is_empty():
		_hud.show_notice(refusal)
		return
	_go_through.call_deferred(door)


## Takes the party through `door` if it still stands in the room and nothing has come to stop them.
func _go_through(door: Door) -> void:
	if not is_instance_valid(door) or not door.is_inside_tree() or not doors_usable():
		return
	if not _refusal(door).is_empty():
		return
	_go.call(door.to_room, door.to_entry)
