class_name TitleScreen
extends Control
## The title: the game's name over Álvar's portrait, large and dim, then Continue (only when a save
## can be continued), New game and Controls. The `confirm` action chooses Continue when it is offered
## and New game otherwise. No control takes keyboard focus, so Space and Enter stay game keys; only
## the buttons stop the mouse.
##
## New game starts at once when there is no save to lose. When there is, the first press asks first:
## the button gives way to `Erase the saved game?` with `Yes, begin anew` and `No`. `No`, the `cancel`
## action (Escape) or the title closing puts the button back. Controls opens the `ControlsCard`; while
## it is open the title reads no keys, and Escape closes the card first.
##
## Texts: the buttons and the question have automatic translation off in the scene and get their text
## from `tr()` in code, set again when the language changes. The game's name is not translated.

signal continue_chosen
## The player chose to begin a new game, after saying yes when a save would be lost.
signal new_game_chosen

## Whether a save would be lost by a new game: Continue is offered.
var _has_save: bool = false

@onready var _continue_button: Button = %ContinueButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _confirm: Control = %Confirm
@onready var _question: Label = %QuestionLabel
@onready var _yes_button: Button = %YesButton
@onready var _no_button: Button = %NoButton
@onready var _controls_button: Button = %ControlsButton
@onready var _controls_card: ControlsCard = %ControlsCard


func _ready() -> void:
	_show_texts()
	_continue_button.pressed.connect(continue_chosen.emit)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_yes_button.pressed.connect(new_game_chosen.emit)
	_no_button.pressed.connect(_take_back)
	_controls_button.pressed.connect(_controls_card.open)


## Shows the title, with Continue offered only when `can_continue`.
func open(can_continue: bool) -> void:
	_has_save = can_continue
	_continue_button.visible = can_continue
	_take_back()
	visible = true


func close() -> void:
	_take_back()
	_controls_card.close()
	visible = false


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	# The card, a child, reads Escape itself after this.
	if not visible or _controls_card.is_open():
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if Input.is_action_just_pressed(&"cancel"):
		_take_back()
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
	_question.text = tr("Erase the saved game?")
	_yes_button.text = tr("Yes, begin anew")
	_no_button.text = tr("No")


func _on_new_game_pressed() -> void:
	if not _has_save:
		new_game_chosen.emit()
		return
	_new_game_button.visible = false
	_confirm.visible = true


## Puts New game back in place of the question.
func _take_back() -> void:
	_confirm.visible = false
	_new_game_button.visible = true
