class_name UnitVisual
extends Node3D
## The figure of a `Unit` or an `Npc`: the human model in its `Dress`, playing the clip that shows
## what its parent is doing. It only reads: it follows a unit's signals and public state each frame and
## changes nothing outside itself. Under a unit, the first rule that holds picks the clip:
##
## 1. fallen: `death`, held on its last frame
## 2. just revived: `death` backwards at double speed
## 3. drinking: `feed`, the model drawn shifted towards the victim so the two figures meet
## 4. stunned, which includes being fed on: `stagger`
## 5. a strike, a Gift or a hit just now: `attack`, `cast` or `hit`, for at most `ONE_SHOT_TIME`; a
##    hit does not cut a strike or a Gift short
## 6. moving: `run` when fast (see `RUN_ABOVE`) or while hastened, else `walk`, at the speed that keeps the
##    feet on the ground
## 7. otherwise `idle`
##
## Anyone else plays `talk` while `speaking` (`sit_talk` when `resting` is `sit`), else `resting`.
## The model's animation runs in the parent's subtree, so it stops whenever the parent stops
## processing.
##
## The dress's head and gear hang from the model's bones, each piece under its own `BoneAttachment3D`,
## the head first. The head and the garments are drawn with the body's own material, as their faces
## point at the palette's own squares. Other cloth is coloured from the dress's palette; cloth with
## shape keys is stretched round the legs by a `ClothFit`; everything else shares one material that
## shows the gear palette. Every one of these materials is the body's with another texture or offset,
## so the gear adds no shader to compile; rigid garments cost nothing per frame.
##
## A unit's marks are drawn here, unshaded so the room's light never changes them: a gold ring on
## the floor while it is the selected member, and a pale drop over its head while it can be fed on.
## The unit says which to show; a fallen unit shows neither.

const HUMAN: PackedScene = preload("res://assets/characters/human/human.glb")
## The colours of every piece that is not cloth: steel, wood, leather.
const GEAR_PALETTE: Texture2D = preload("res://assets/gear/palette-gear.png")
## The model's height in metres at scale 1.
const MODEL_HEIGHT: float = 1.83
## Seconds to blend from one clip into the next.
const BLEND: float = 0.15
## A strike, a Gift or a hit shows for its clip's length, but no longer than this.
const ONE_SHOT_TIME: float = 0.7
## A unit starts to count as moving above this flat speed, in metres per second, and stops below
## `STOPPED`, so a unit nudged at about one speed does not flicker between the two.
const MOVING: float = 0.15
const STOPPED: float = 0.05
## A moving unit takes up `run` above this flat speed, in metres per second, and goes back to `walk`
## below `WALK_BELOW`: played fast enough to keep up with 3-4 m/s, `walk` turns into a shuffle.
const RUN_ABOVE: float = 2.4
const WALK_BELOW: float = 2.0
## While drinking, the model is drawn up to `FEED_REACH` metres towards the victim, stopping
## `FEED_GAP` from it, easing in and out over `FEED_EASE` seconds. The unit itself stays where it is.
const FEED_REACH: float = 0.8
const FEED_GAP: float = 0.55
const FEED_EASE: float = 0.2
## How fast a revived unit plays its fall backwards.
const RISE_SPEED: float = 2.0
## The ground speed, in metres per second at scale 1, at which each clip's planted foot stays put:
## measured from the clips' foot bones.
const STRIDE_SPEED: Dictionary = {&"walk": 1.06, &"run": 5.4}
## In the Fury the palette is darkened by `FURY_TINT` and glows `FURY_GLOW`, so even a dark figure
## turns red.
const FURY_TINT: Color = Color(1.0, 0.5, 0.45)
const FURY_GLOW: Color = Color(0.5, 0.03, 0.02)
## Every figure carries a faint light of its own, so it stays distinguishable in the darkest corner
## of a room without lighting the room more: its own colours at `LIFT` of their strength, plus the
## cool `LIFT_FLOOR` at the same strength, which keeps even a figure dressed in black off the black
## floor. The Fury's glow takes its place.
const LIFT: float = 0.16
const LIFT_FLOOR: Color = Color(0.3, 0.34, 0.46)
## The selected member's ring: its outer radius and width, in metres, and its colour.
const SELECTED_RADIUS: float = 0.55
const SELECTED_WIDTH: float = 0.035
const SELECTED_COLOUR: Color = Color(0.95, 0.74, 0.22)
## The drop's middle is this far above the top of the head.
const DROP_ABOVE: float = 0.32
## Clips in which the legs barely move, so cloth settled in one stays settled.
const STILL_CLIPS: Array[StringName] = [&"idle", &"talk", &"sit", &"sit_talk", &"death"]
## Seconds of standing after which every cloth key has let go fully (see `ClothFit.SETTLE`).
const SETTLED_AFTER: float = 1.0
## Regions of the palette, which is this many squares wide.
const PALETTE_SQUARES: int = 16

## The material every piece with its own colours shares: the body's, showing the gear palette.
static var _own_colours: StandardMaterial3D

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
var _skeleton: Skeleton3D
var _material: StandardMaterial3D
## The body's material and the cloth's, which the Fury tints together.
var _materials: Array[StandardMaterial3D] = []
## The pieces' attachments, under the skeleton.
var _gear: Array[BoneAttachment3D] = []
var _fits: Array[ClothFit] = []
## Tells whether the figure is on screen, for the cloth fit.
var _on_screen: VisibleOnScreenNotifier3D
## Cloth fitting: whether this pose is the skipped one of two, the time since the last fit, whether
## the last fit moved nothing, and the clip it was in.
var _fit_turn: bool = false
var _fit_time: float = 0.0
var _cloth_settled: bool = false
var _settled_clip: StringName = &""
var _selected_ring: FloorRing
var _feed_drop: FeedDrop
## What the unit asked to show; shown only while it stands.
var _selected_wanted: bool = false
var _feed_wanted: bool = false
## What is playing, and whether it is the fall played backwards.
var _clip: StringName = &""
var _rising: bool = false
var _one_shot: StringName = &""
var _one_shot_left: float = 0.0
var _rising_left: float = 0.0
var _tinted: bool = false
var _moving: bool = false
var _running: bool = false
## How far the feed's lean towards the victim has eased in, from 0 to 1.
var _lean: float = 0.0
## Where the lean goes, flat in world space, as of the last frame of drinking.
var _lean_offset: Vector3 = Vector3.ZERO
## The material's own colour, which the Fury's tint leaves and gives back.
var _albedo: Color


func _ready() -> void:
	_model = HUMAN.instantiate()
	_model.name = &"Model"
	add_child(_model)
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_mesh = _model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_skeleton.skeleton_updated.connect(_fit_cloth)
	# Its own copy, so one figure's palette and tint never show on another.
	_material = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	# On from the start, so the lift and the Fury change uniforms and not the shader.
	_material.emission_enabled = true
	_albedo = _material.albedo_color
	_lift(_material)
	_mesh.material_override = _material
	_materials.append(_material)
	_on_screen = VisibleOnScreenNotifier3D.new()
	_on_screen.name = &"OnScreen"
	_on_screen.aabb = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.3, 2.0))
	add_child(_on_screen)
	_selected_ring = FloorRing.new(SELECTED_RADIUS, SELECTED_WIDTH, SELECTED_COLOUR)
	_selected_ring.name = &"SelectedRing"
	_selected_ring.visible = false
	add_child(_selected_ring)
	_feed_drop = FeedDrop.new()
	_feed_drop.name = &"FeedDrop"
	_feed_drop.visible = false
	add_child(_feed_drop)
	_wear()
	_unit = get_parent() as Unit
	if _unit != null:
		_follow(_unit)
	# The parent is not ready yet, so its state is not read before the first frame.
	_show(&"idle", false)


func _process(delta: float) -> void:
	_one_shot_left = maxf(_one_shot_left - delta, 0.0)
	_rising_left = maxf(_rising_left - delta, 0.0)
	_show(_choose(), _is_rising())
	if _unit != null:
		_lean_towards_victim(delta)
	var tinted: bool = _unit != null and _unit.is_in_fury()
	if tinted != _tinted:
		_tinted = tinted
		for material: StandardMaterial3D in _materials:
			_tint(material)


## The clip on show; a revived unit's fall played backwards is `death` too.
func clip() -> StringName:
	return _clip


func model() -> Node3D:
	return _model


## Shows the selected member's ring, while the unit stands.
func show_selected_mark(on: bool) -> void:
	_selected_wanted = on
	_show_marks()


## Shows the drop over the head, while the unit stands.
func show_feed_mark(on: bool) -> void:
	_feed_wanted = on
	_show_marks()


## Fits the cloth to the pose on show at once and lets it settle there fully, as if the figure had
## stood in it a while: for a figure that does not process, such as a portrait's. A figure `lying` on the
## floor (in `death`) has its hem laid flat, as in the game.
func settle_cloth(lying: bool = false) -> void:
	for fit: ClothFit in _fits:
		fit.fit(SETTLED_AFTER, lying)


## The fits of its cloth pieces that stretch, so a test can call them: headless no figure is on screen,
## and only a figure on screen fits its cloth itself.
func cloth_fits() -> Array[ClothFit]:
	return _fits.duplicate()


func is_selected_mark_shown() -> bool:
	return _selected_ring.visible


func is_feed_mark_shown() -> bool:
	return _feed_drop.visible


func _show_marks() -> void:
	var standing: bool = _unit != null and _unit.is_alive()
	_selected_ring.visible = _selected_wanted and standing
	_feed_drop.visible = _feed_wanted and standing


func _wear() -> void:
	if dress == null:
		return
	_model.scale = Vector3.ONE * (dress.height / MODEL_HEIGHT)
	_feed_drop.position.y = dress.height + DROP_ABOVE
	if dress.palette != null:
		_material.albedo_texture = dress.palette
		_tint(_material)
	_hang_gear()


## Hangs the dress's head and then each piece of its gear from its bone, in place of any hung before.
## A dress without a head is an error, and the figure is drawn headless; so is one with no garment on
## any of `Dress.CLOTHED_BONES`, and the figure is drawn hollow there.
func _hang_gear() -> void:
	for attachment: BoneAttachment3D in _gear:
		_skeleton.remove_child(attachment)
		attachment.queue_free()
	_gear.clear()
	_fits.clear()
	_cloth_settled = false
	_materials.resize(1)
	if dress.head == null:
		push_error("The dress %s has no head" % _dress_name())
	else:
		_hang(dress.head, true)
	var bare: Array[StringName] = Dress.CLOTHED_BONES.duplicate()
	for piece: GearPiece in dress.gear:
		_hang(piece, false)
		bare.erase(piece.bone)
	if not bare.is_empty():
		push_error("The dress %s leaves the body bare at %s" % [_dress_name(), ", ".join(bare)])


func _dress_name() -> String:
	return dress.palette_name() if dress.resource_path.is_empty() else dress.resource_path


## Hangs `piece` from its bone: a head or a piece of the palette's own squares drawn with the body's
## material, other cloth with its region's, anything else with the shared one of its own colours.
func _hang(piece: GearPiece, head: bool) -> void:
	var bone: int = _skeleton.find_bone(piece.bone)
	if bone < 0 or piece.scene == null:
		push_error("The model has no bone %s for %s" % [piece.bone, piece.resource_path])
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = piece.scene.resource_path.get_file().get_basename()
	attachment.bone_name = piece.bone
	_skeleton.add_child(attachment)
	_gear.append(attachment)
	var worn: Node3D = piece.scene.instantiate()
	attachment.add_child(worn)
	worn.transform = _hang_at_rest(bone)
	var material: StandardMaterial3D = _material
	if not head and not piece.own_squares:
		material = _cloth_material(piece.region) if piece.cloth else _shared_own_colours(_material)
	for mesh: MeshInstance3D in worn.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
		if piece.cloth:
			var fit := ClothFit.new(mesh, _skeleton, bone, worn.transform * mesh.transform, piece.clearance,
					piece.shape)
			if fit.is_fitting():
				_fits.append(fit)


## Where a piece modelled in the model's frame at rest, with its origin at `bone`'s rest head, lies
## relative to that bone: the bone's rest turn undone, so the piece keeps the model's axes at rest.
func _hang_at_rest(bone: int) -> Transform3D:
	var rig := Transform3D()  # the skeleton's frame in the model's
	var node: Node = _skeleton
	while node != _model:
		rig = (node as Node3D).transform * rig
		node = node.get_parent()
	var rest: Transform3D = _skeleton.get_bone_global_rest(bone)
	return (rig * rest).affine_inverse() * Transform3D(Basis.IDENTITY, rig * rest.origin)


## This figure's cloth material for `region`: the body's, shifted to that square of the palette.
func _cloth_material(region: Dress.Region) -> StandardMaterial3D:
	var material := _material.duplicate() as StandardMaterial3D
	material.albedo_color = _albedo
	material.uv1_offset = Vector3(float(region) / PALETTE_SQUARES, 0.0, 0.0)
	_materials.append(material)
	_tint(material)
	return material


func _tint(material: StandardMaterial3D) -> void:
	material.albedo_color = _albedo * FURY_TINT if _tinted else _albedo
	if _tinted:
		material.emission = FURY_GLOW
		material.emission_texture = null
		material.emission_energy_multiplier = 1.0
	else:
		_lift(material)


## Gives `material` the faint light of its own colours (see `LIFT`): the emission adds its texture's
## colour to `LIFT_FLOOR`, both at `LIFT` of their strength.
static func _lift(material: StandardMaterial3D) -> void:
	material.emission = LIFT_FLOOR
	material.emission_texture = material.albedo_texture
	material.emission_energy_multiplier = LIFT


## Made once, from a body's material (`body`) as it stands untinted.
static func _shared_own_colours(body: StandardMaterial3D) -> StandardMaterial3D:
	if _own_colours == null:
		_own_colours = body.duplicate() as StandardMaterial3D
		_own_colours.albedo_color = Color.WHITE
		_own_colours.albedo_texture = GEAR_PALETTE
		_lift(_own_colours)
	return _own_colours


## Fits the cloth to the pose just set, every second pose, and only while the figure is on screen. A
## figure settled in a still clip (one that barely moves the legs, or a fall held on its last frame)
## with its cloth settled is not fitted again until its clip changes. A fallen figure's skirt lies
## flat: hung rigidly from the hips, it would stand up off the floor round the legs.
func _fit_cloth() -> void:
	if _fits.is_empty():
		return
	_fit_time += get_process_delta_time()
	_fit_turn = not _fit_turn
	if _fit_turn or not _on_screen.is_on_screen():
		return
	var still: bool = STILL_CLIPS.has(_clip) and not _rising
	if still and _cloth_settled and _clip == _settled_clip:
		_fit_time = 0.0
		return
	var lying: bool = _clip == &"death" and not _rising
	var moved: bool = false
	for fit: ClothFit in _fits:
		moved = fit.fit(_fit_time, lying) or moved
	_fit_time = 0.0
	_cloth_settled = not moved
	_settled_clip = _clip


func _follow(unit: Unit) -> void:
	unit.was_hit.connect(_on_hit.unbind(2))
	unit.revived.connect(_on_revived.unbind(1))
	unit.died.connect(_show_marks.unbind(1))
	unit.revived.connect(_show_marks.unbind(1))
	var melee := unit.get_node_or_null(^"Melee") as MeleeAttack
	if melee != null:
		melee.hit.connect(_start_one_shot.bind(&"attack").unbind(2))
	var gifts := unit.get_node_or_null(^"Gifts") as GiftUser
	if gifts != null:
		gifts.gift_used.connect(_start_one_shot.bind(&"cast").unbind(2))


func _choose() -> StringName:
	if _unit == null:
		if not speaking:
			return resting
		# A seated character stays seated to speak.
		return &"sit_talk" if resting == &"sit" else &"talk"
	var speed: float = _flat_speed()
	_moving = speed > (STOPPED if _moving else MOVING)
	_running = _moving and speed > (WALK_BELOW if _running else RUN_ABOVE)
	var higher: StringName = &""
	if not _unit.is_alive() or _is_rising():
		higher = &"death"
	elif _unit.is_feeding():
		higher = &"feed"
	elif _unit.is_stunned():
		higher = &"stagger"
	if not higher.is_empty():
		# A strike or a hit cut short by a higher rule does not show once that rule ends.
		_one_shot_left = 0.0
		return higher
	if _one_shot_left > 0.0:
		return _one_shot
	if _moving:
		return &"run" if _running or _unit.speed_multiplier() > 1.0 else &"walk"
	return &"idle"


## Eases the model towards the victim while drinking, and back once the drinking ends.
func _lean_towards_victim(delta: float) -> void:
	var victim: Unit = _unit.feed_target() if _unit.is_feeding() else null
	_lean = move_toward(_lean, 1.0 if victim != null else 0.0, delta / FEED_EASE)
	if victim != null:
		var gap: Vector3 = victim.global_position - global_position
		gap.y = 0.0
		var reach: float = clampf(gap.length() - FEED_GAP, 0.0, FEED_REACH)
		_lean_offset = gap.normalized() * reach
	if _lean == 0.0:
		_lean_offset = Vector3.ZERO
	_model.position = to_local(global_position + _lean_offset * _lean)


func _is_rising() -> bool:
	return _rising_left > 0.0 and _unit != null and _unit.is_alive()


## Plays `clip`, blending from what showed before, unless it already plays; `rising` plays the fall
## backwards. `restart` plays it again from its start even when it already plays.
func _show(clip_name: StringName, rising: bool, restart: bool = false) -> void:
	if clip_name != _clip or rising != _rising or restart:
		# A finished clip that does not loop has stopped, but its last pose still blends out.
		var blend: float = 0.0 if _clip.is_empty() else BLEND
		var again: bool = clip_name == _clip and rising == _rising
		_clip = clip_name
		_rising = rising
		if rising:
			_player.play(clip_name, blend, -RISE_SPEED, true)
		else:
			_player.play(clip_name, blend)
		if again:
			_player.seek(0.0, true)
		# Posed at once: a unit spawned or revived while held does not process, and would show its rest pose.
		_player.advance(0.0)
	_player.speed_scale = 1.0
	if STRIDE_SPEED.has(clip_name):
		_player.speed_scale = _flat_speed() / (STRIDE_SPEED[clip_name] * _model.scale.x)


func _flat_speed() -> float:
	return Vector2(_unit.velocity.x, _unit.velocity.z).length()


func _start_one_shot(clip_name: StringName) -> void:
	_one_shot = clip_name
	_one_shot_left = minf(_player.get_animation(clip_name).length, ONE_SHOT_TIME)
	var shown: StringName = _choose()
	# The one-shot starts again from its start; anything a higher rule shows carries on as it was.
	_show(shown, _is_rising(), shown == clip_name)


func _on_hit() -> void:
	if _one_shot_left > 0.0 and _one_shot in [&"attack", &"cast"]:
		return
	_start_one_shot(&"hit")


func _on_revived() -> void:
	_rising_left = _player.get_animation(&"death").length / RISE_SPEED
	_show(&"death", true)
