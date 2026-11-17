class_name Npc
extends Interactable
## Someone in a room to talk to: Álvar walks up to them and uses them, which asks for their
## conversation; a click on them sends him, whoever is selected. A use that `talk_allowed` refuses does not count: nothing is emitted. Story flags can show or hide them; a hidden one has its collider disabled, so it is
## neither clicked nor used.

## A unit used them: the conversation `dialogue` at the cue `title` should start.
signal talk_requested(npc: Npc, by: Unit)

## Their conversation, a `.dialogue` file.
@export var dialogue: Resource
## The cue their conversation starts at.
@export var title: String = "start"
## When set, they are shown only while this story flag is set.
@export var shown_if: StringName = &""
## When set, they are hidden while this story flag is set.
@export var hidden_if: StringName = &""
## What they wear.
@export var dress: Dress
## Whether they sit while no one speaks to them.
@export var sitting: bool = false

## Asked, with no arguments, at each use; when set and it answers false, the use is refused. Set by
## whoever answers `talk_requested`, so a talk that would be refused is not a use.
var talk_allowed: Callable = Callable()

@onready var _visual: UnitVisual = $Visual


func _init() -> void:
	leader_only = true


func _ready() -> void:
	_visual.dress = dress
	_visual.resting = &"sit" if sitting else &"idle"


## Shows them speaking, or not. The conversation tells each character whether the line on show is theirs.
func set_speaking(on: bool) -> void:
	_visual.speaking = on


## Only Álvar, and only while shown and with something to say.
func can_be_used_by(unit: Unit) -> bool:
	return unit != null and unit.member_id == GameState.LEADER and visible and dialogue != null


## Their ring shows only while a talk with them would be allowed now.
func offers_use_to(unit: Unit) -> bool:
	return can_be_used_by(unit) and (not talk_allowed.is_valid() or talk_allowed.call())


func use(by: Unit) -> bool:
	if talk_allowed.is_valid() and not talk_allowed.call():
		return false
	if not super(by):
		return false
	talk_requested.emit(self, by)
	return true


## Shows or hides them by the flags in `state`: shown when `shown_if` is empty or set and `hidden_if` is
## empty or not set.
func show_by(state: GameState) -> void:
	var shown: bool = ((shown_if.is_empty() or state.has_flag(shown_if))
			and (hidden_if.is_empty() or not state.has_flag(hidden_if)))
	visible = shown
	for child: Node in get_children():
		if child is CollisionShape3D:
			# Deferred, as a flag can change during a physics callback.
			child.set_deferred(&"disabled", not shown)
