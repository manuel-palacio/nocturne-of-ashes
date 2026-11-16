class_name Main
extends Node3D
## Runs the vault room: spawns the party and the crusaders, a sergeant among each group, wires camera,
## input and HUD, hands control to the selected party member, raises fallen companions once a fight is
## over, marks the enemies the selected member can feed on, and restarts after Álvar's fall.

## Emitted at the end of `start_room()`, once the new round's units are in place.
signal room_started
## Emitted when a living party member becomes the selected one.
signal selection_changed(unit: Unit)
## Emitted once per round, when the last enemy falls.
signal room_cleared
## Emitted when a party member falls or rises.
signal party_changed
## Emitted when the world pause turns on or off.
signal pause_changed(paused: bool)

const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const ZAHRA: PackedScene = preload("res://scenes/units/zahra.tscn")
const GONZALO: PackedScene = preload("res://scenes/units/gonzalo.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")
const SERGEANT: PackedScene = preload("res://scenes/units/crusader_sergeant.tscn")

## Seconds without a fight before fallen companions rise.
@export var calm_time: float = 3.0
## The enemy spawn markers that get a sergeant instead of a crusader, one per group.
@export var sergeant_spawns: Array[StringName] = [&"EnemySpawn3", &"EnemySpawn6"]

## Álvar, Zahra and Gonzalo, in that order.
var party: Array[Unit] = []
## Always `party[0]`, Álvar, whose fall ends the round.
var player: Unit
var selected: Unit
var enemies: Array[Unit] = []

## Seconds since a fight was last on or a party member last fell.
var _calm_for: float = 0.0
var _cleared: bool = false
var _paused: bool = false

@onready var input: PlayerInput = $PlayerInput
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var _room: Node3D = $VaultRoom
@onready var _units: Node3D = $Units


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
	input.targeting_changed.connect(hud.show_targeting)
	hud.member_pressed.connect(input.press_member)
	hud.gift_chosen.connect(input.press_gift)
	selection_changed.connect(hud.show_selected)
	pause_changed.connect(hud.set_paused)
	room_cleared.connect(hud.show_cleared)
	start_room()


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


## Clears the last round's units and spawns a fresh one, with Álvar selected.
func start_room() -> void:
	set_paused(false)
	input.cancel_targeting()
	for unit: Node in _units.get_children():
		# Out of the tree at once, so no new unit finds an old one in the "units" group.
		_units.remove_child(unit)
		unit.queue_free()
	party.clear()
	enemies.clear()
	selected = null
	_calm_for = 0.0
	_cleared = false

	for spawn: Array in [[ALVAR, ^"PlayerSpawn"], [ZAHRA, ^"CompanionSpawn1"], [GONZALO, ^"CompanionSpawn2"]]:
		var member: Unit = _spawn(spawn[0], _room.get_node(spawn[1]))
		member.died.connect(_on_member_died)
		member.revived.connect(_on_member_revived)
		party.append(member)
	player = party[0]
	hud.bind_party(party)
	hud.hide_fallen()
	hud.hide_cleared()
	for marker: Node in _room.get_children():
		if marker is Marker3D and marker.name.begins_with("EnemySpawn"):
			var scene: PackedScene = SERGEANT if sergeant_spawns.has(StringName(marker.name)) else CRUSADER
			enemies.append(_spawn(scene, marker))

	input.rig = rig
	input.enabled = true
	select(player)
	rig.snap_to_target()
	room_started.emit()


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
	if not player.is_alive() or unit == null or not party.has(unit) or not unit.is_alive():
		return
	selected = unit
	rig.target = unit
	input.unit = unit
	for member: Unit in party:
		if member.is_alive():
			_steer_brain(member)
	_update_feed_marks()
	selection_changed.emit(unit)


## Selects the next living party member after the selected one, wrapping round. Ignored while Álvar is down.
func select_next() -> void:
	if not player.is_alive():
		return
	var at: int = party.find(selected)
	for step: int in range(1, party.size() + 1):
		var candidate: Unit = party[(at + step) % party.size()]
		if candidate.is_alive():
			select(candidate)
			return


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
		room_cleared.emit()
		_revive_fallen()
	if fight_is_on():
		_calm_for = 0.0
		return
	_calm_for += delta
	if _calm_for >= calm_time:
		_revive_fallen()


## Marks exactly the living enemies the selected member can feed on, whatever its Blood; none while
## Álvar is down.
func _update_feed_marks() -> void:
	var feeder: Unit = selected if player != null and player.is_alive() else null
	for enemy: Unit in enemies:
		enemy.set_feed_mark(feeder != null and feeder.can_feed_on(enemy))


func _revive_fallen() -> void:
	for member: Unit in party:
		if not member.is_alive():
			member.revive()


## The selected member's brain is off; every other member's follows the selected one.
## The setter forgets the brain's chosen target, so `enabled` is only written when it changes.
func _steer_brain(member: Unit) -> void:
	var brain: CombatBrain = member.get_node(^"Brain")
	brain.leader = selected
	var wanted: bool = member != selected
	if brain.enabled != wanted:
		brain.enabled = wanted


## True when the engine's locale is no longer the system's: `--language` (or code) chose it. Godot keeps
## `--language` out of `OS.get_cmdline_args()`, so the locales are compared. When they match, picking
## again gives the same language, or English where the system's has no texts.
func _locale_chosen_before_start() -> bool:
	return TranslationServer.get_locale() != TranslationServer.standardize_locale(OS.get_locale())


func _spawn(scene: PackedScene, marker: Node3D) -> Unit:
	var unit: Unit = scene.instantiate()
	_units.add_child(unit)
	unit.global_transform = marker.global_transform
	return unit


func _on_member_died(unit: Unit) -> void:
	_calm_for = 0.0
	party_changed.emit()
	if unit == player:
		input.cancel_targeting()
		input.enabled = false
		_update_feed_marks()
		hud.show_fallen()
	elif unit == selected:
		select(player)


func _on_member_revived(unit: Unit) -> void:
	_steer_brain(unit)
	party_changed.emit()
