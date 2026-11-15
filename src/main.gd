class_name Main
extends Node3D
## Runs the vault room: spawns Álvar and the crusaders, wires camera, input and HUD, and restarts after a fall.

## Emitted at the end of `start_room()`, once the new round's units are in place.
signal room_started

const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")

var player: Unit
var enemies: Array[Unit] = []

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


## Clears the last round's units and spawns a fresh one.
func start_room() -> void:
	for unit: Node in _units.get_children():
		# Out of the tree at once, so no new unit finds an old one in the "units" group.
		_units.remove_child(unit)
		unit.queue_free()
	enemies.clear()

	player = _spawn(ALVAR, _room.get_node(^"PlayerSpawn"))
	player.died.connect(_on_player_died)
	for marker: Node in _room.get_children():
		if marker is Marker3D and marker.name.begins_with("EnemySpawn"):
			enemies.append(_spawn(CRUSADER, marker))

	rig.target = player
	rig.snap_to_target()
	input.unit = player
	input.rig = rig
	input.enabled = true
	hud.bind(player)
	hud.hide_fallen()
	room_started.emit()


func enemies_alive() -> int:
	var alive: int = 0
	for enemy: Unit in enemies:
		if enemy.is_alive():
			alive += 1
	return alive


func _spawn(scene: PackedScene, marker: Node3D) -> Unit:
	var unit: Unit = scene.instantiate()
	_units.add_child(unit)
	unit.global_transform = marker.global_transform
	return unit


func _on_player_died(_unit: Unit) -> void:
	input.enabled = false
	hud.show_fallen()
