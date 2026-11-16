class_name Main
extends Node3D
## Runs the vault room: spawns the party and the crusaders, wires camera, input and HUD, hands control
## to the selected party member, raises fallen companions once a fight is over, and restarts after
## Álvar's fall.

## Emitted at the end of `start_room()`, once the new round's units are in place.
signal room_started
## Emitted when a living party member becomes the selected one.
signal selection_changed(unit: Unit)
## Emitted once per round, when the last enemy falls.
signal room_cleared
## Emitted when a party member falls or rises.
signal party_changed

const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const ZAHRA: PackedScene = preload("res://scenes/units/zahra.tscn")
const GONZALO: PackedScene = preload("res://scenes/units/gonzalo.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")

## Seconds without a fight before fallen companions rise.
@export var calm_time: float = 3.0

## Álvar, Zahra and Gonzalo, in that order.
var party: Array[Unit] = []
## Always `party[0]`, Álvar, whose fall ends the round.
var player: Unit
var selected: Unit
var enemies: Array[Unit] = []

## Seconds since a fight was last on or a party member last fell.
var _calm_for: float = 0.0
var _cleared: bool = false

@onready var input: PlayerInput = $PlayerInput
@onready var rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var _room: Node3D = $VaultRoom
@onready var _units: Node3D = $Units


func _ready() -> void:
	start_room()


func _process(_delta: float) -> void:
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if not player.is_alive() and Input.is_action_just_pressed(&"confirm"):
		start_room()


func _physics_process(delta: float) -> void:
	_advance_fight_flow(delta)


## Clears the last round's units and spawns a fresh one, with Álvar selected.
func start_room() -> void:
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
	for marker: Node in _room.get_children():
		if marker is Marker3D and marker.name.begins_with("EnemySpawn"):
			enemies.append(_spawn(CRUSADER, marker))

	input.rig = rig
	input.enabled = true
	select(player)
	rig.snap_to_target()
	hud.bind(player)
	hud.hide_fallen()
	room_started.emit()


## Gives camera and input to `unit` and sets the other living members following it.
## Ignored unless `unit` is a living party member.
func select(unit: Unit) -> void:
	if unit == null or not party.has(unit) or not unit.is_alive():
		return
	selected = unit
	rig.target = unit
	input.unit = unit
	for member: Unit in party:
		if member.is_alive():
			_steer_brain(member)
	selection_changed.emit(unit)


## Selects the next living party member after the selected one, wrapping round.
func select_next() -> void:
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


func _spawn(scene: PackedScene, marker: Node3D) -> Unit:
	var unit: Unit = scene.instantiate()
	_units.add_child(unit)
	unit.global_transform = marker.global_transform
	return unit


func _on_member_died(unit: Unit) -> void:
	_calm_for = 0.0
	party_changed.emit()
	if unit == player:
		input.enabled = false
		hud.show_fallen()
	elif unit == selected:
		select(player)


func _on_member_revived(unit: Unit) -> void:
	_steer_brain(unit)
	party_changed.emit()
