class_name UnitVisual
extends Node3D
## The figure of a `Unit` or an `Npc`: the human model in its `Dress`, playing the clip that shows
## what its parent is doing. It only reads: it follows a unit's signals and public state each frame and
## changes nothing outside itself. Under a unit, the first rule that holds picks the clip:
##
## 1. fallen: `death`, held on its last frame
## 2. just revived: `death` backwards at double speed
## 3. drinking: `feed`
## 4. stunned, which includes being fed on: `stagger`
## 5. a strike, a Gift or a hit just now: `attack`, `cast` or `hit`, for at most `ONE_SHOT_TIME`; a
##    hit does not cut a strike or a Gift short
## 6. walking: `run` while hastened, else `walk`, at the speed that keeps the feet on the ground
## 7. otherwise `idle`
##
## Anyone else plays `talk` while `speaking`, else `resting`. The model's animation runs in the
## parent's subtree, so it stops whenever the parent stops processing.

const HUMAN: PackedScene = preload("res://assets/characters/human/human.glb")
## The model's height in metres at scale 1.
const MODEL_HEIGHT: float = 1.83
## Seconds to blend from one clip into the next.
const BLEND: float = 0.15
## A strike, a Gift or a hit shows for its clip's length, but no longer than this.
const ONE_SHOT_TIME: float = 0.7
## Flat metres per second above which a unit counts as walking.
const MOVING: float = 0.1
## How fast a revived unit plays its fall backwards.
const RISE_SPEED: float = 2.0
## The ground speed, in metres per second at scale 1, at which each clip's planted foot stays put:
## measured from the clips' foot bones.
const STRIDE_SPEED: Dictionary = {&"walk": 1.06, &"run": 5.4}
## In the Fury the palette is darkened by `FURY_TINT` and glows `FURY_GLOW`, so even a dark figure
## turns red.
const FURY_TINT: Color = Color(1.0, 0.5, 0.45)
const FURY_GLOW: Color = Color(0.5, 0.03, 0.02)

## What it wears; the model's own palette without one.
@export var dress: Dress:
	set(value):
		dress = value
		if is_node_ready():
			_wear()

## Away from a unit: the clip shown while not speaking.
var resting: StringName = &"idle"
## Away from a unit: whether it is speaking in a conversation.
var speaking: bool = false

var _unit: Unit
var _model: Node3D
var _player: AnimationPlayer
var _mesh: MeshInstance3D
var _material: StandardMaterial3D
## What is playing, and whether it is the fall played backwards.
var _clip: StringName = &""
var _rising: bool = false
var _one_shot: StringName = &""
var _one_shot_left: float = 0.0
var _rising_left: float = 0.0
var _tinted: bool = false


func _ready() -> void:
	_model = HUMAN.instantiate()
	_model.name = &"Model"
	add_child(_model)
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_mesh = _model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	# Its own copy, so one figure's palette and tint never show on another.
	_material = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	# On from the start, so the Fury changes a colour and not the shader.
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	_mesh.material_override = _material
	_wear()
	_unit = get_parent() as Unit
	if _unit != null:
		_follow(_unit)
	# The parent is not ready yet, so its state is not read before the first frame.
	_show(&"idle", false)


func _process(delta: float) -> void:
	_one_shot_left = maxf(_one_shot_left - delta, 0.0)
	_rising_left = maxf(_rising_left - delta, 0.0)
	_show(_choose(), _rising_left > 0.0 and _unit.is_alive())
	var tinted: bool = _unit != null and _unit.is_in_fury()
	if tinted != _tinted:
		_tinted = tinted
		_material.albedo_color = FURY_TINT if tinted else Color.WHITE
		_material.emission = FURY_GLOW if tinted else Color.BLACK


## The clip on show; a revived unit's fall played backwards is `death` too.
func clip() -> StringName:
	return _clip


func model() -> Node3D:
	return _model


func _wear() -> void:
	if dress == null:
		return
	_model.scale = Vector3.ONE * (dress.height / MODEL_HEIGHT)
	if dress.palette != null:
		_material.albedo_texture = dress.palette


func _follow(unit: Unit) -> void:
	unit.was_hit.connect(_on_hit.unbind(2))
	unit.revived.connect(_on_revived.unbind(1))
	var melee := unit.get_node_or_null(^"Melee") as MeleeAttack
	if melee != null:
		melee.hit.connect(_start_one_shot.bind(&"attack").unbind(2))
	var gifts := unit.get_node_or_null(^"Gifts") as GiftUser
	if gifts != null:
		gifts.gift_used.connect(_start_one_shot.bind(&"cast").unbind(2))


func _choose() -> StringName:
	if _unit == null:
		return &"talk" if speaking else resting
	if not _unit.is_alive() or _rising_left > 0.0:
		return &"death"
	if _unit.is_feeding():
		return &"feed"
	if _unit.is_stunned():
		return &"stagger"
	if _one_shot_left > 0.0:
		return _one_shot
	if _flat_speed() > MOVING:
		return &"run" if _unit.speed_multiplier() > 1.0 else &"walk"
	return &"idle"


## Plays `clip`, blending, unless it already plays; `rising` plays the fall backwards.
func _show(clip_name: StringName, rising: bool) -> void:
	if clip_name != _clip or rising != _rising:
		_clip = clip_name
		_rising = rising
		var blend: float = BLEND if _player.has_animation(_player.current_animation) else 0.0
		if rising:
			_player.play(clip_name, blend, -RISE_SPEED, true)
		else:
			_player.play(clip_name, blend)
	_player.speed_scale = 1.0
	if STRIDE_SPEED.has(clip_name):
		_player.speed_scale = _flat_speed() / (STRIDE_SPEED[clip_name] * _model.scale.x)


func _flat_speed() -> float:
	return Vector2(_unit.velocity.x, _unit.velocity.z).length()


func _start_one_shot(clip_name: StringName) -> void:
	_one_shot = clip_name
	_one_shot_left = minf(_player.get_animation(clip_name).length, ONE_SHOT_TIME)
	# Played again from its start, even when the same clip shows.
	_clip = &""
	_show(_choose(), false)


func _on_hit() -> void:
	if _one_shot_left > 0.0 and _one_shot in [&"attack", &"cast"]:
		return
	_start_one_shot(&"hit")


func _on_revived() -> void:
	_rising_left = _player.get_animation(&"death").length / RISE_SPEED
	_show(&"death", true)
