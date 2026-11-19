class_name TitleScreen
extends Control
## The title: the game's name over Álvar's portrait, large and dim, then Continue (only when a save
## can be continued), New game and Controls. The `confirm` action chooses Continue when it is offered
## and New game otherwise. No control takes keyboard focus, so Space and Enter stay game keys; only
## the buttons stop the mouse. Controls opens the `ControlsCard`; while it is open the title reads no
## keys, and the card closes on Escape.
##
## Texts: the buttons have automatic translation off in the scene and get their text from `tr()` in
## code, set again when the language changes. The game's name is not translated.

signal continue_chosen
signal new_game_chosen

@onready var _continue_button: Button = %ContinueButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _controls_button: Button = %ControlsButton
@onready var _controls_card: ControlsCard = %ControlsCard


func _ready() -> void:
	_show_texts()
	_continue_button.pressed.connect(continue_chosen.emit)
	_new_game_button.pressed.connect(new_game_chosen.emit)
	_controls_button.pressed.connect(_controls_card.open)


## Shows the title, with Continue offered only when `can_continue`.
func open(can_continue: bool) -> void:
	_continue_button.visible = can_continue
	visible = true


func close() -> void:
	_controls_card.close()
	visible = false


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	# The card, a child, reads Escape itself after this.
	if not visible or _controls_card.is_open():
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if not Input.is_action_just_pressed(&"confirm"):
		return
	if _continue_button.visible:
		continue_chosen.emit()
	else:
		new_game_chosen.emit()


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()


func _show_texts() -> void:
	_continue_button.text = tr("Continue")
	_new_game_button.text = tr("New game")
	_controls_button.text = tr("Controls")
