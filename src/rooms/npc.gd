class_name Npc
extends Interactable
## Someone in a room to talk to: a unit walks up to them and uses them, which asks for their
## conversation. Story flags can show or hide them; a hidden one has its collider disabled, so it is
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
@export var colour: Color = Color(0.55, 0.5, 0.45)

@onready var _body: MeshInstance3D = $Body


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	_body.material_override = material


## Only while shown and with something to say.
func can_be_used_by(_unit: Unit) -> bool:
	return visible and dialogue != null


func use(by: Unit) -> bool:
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
