class_name CameraRig
extends Node3D
## Follows `target` across the floor with a pitched camera that can be rotated and zoomed. Its focus
## point (the rig's position, which the camera looks at) is the target's, kept inside the room's floor
## shrunk by a margin, so the view never centres on the dark beyond a wall. The margins follow the view,
## at any zoom and turn: from the walls at the screen's sides, `side_fraction` of the view's half-width
## on the floor; from the wall at its bottom, nearest the camera, `near_fraction` of how far the floor
## is seen toward the camera, which leaves room for the HUD along the bottom edge; from the wall at its
## top, `far_fraction` of that, less, so the wall ahead and its doors stay in sight. At a fraction of 1
## a wall comes to the screen's edge and no further in. The wall at the screen's left, where the HUD's
## party panels are, is held further off when `panel_reserve_px` asks for it, so the feet of a unit by
## that wall are drawn right of the panels, at any turn (the dark beyond the wall goes under them); its
## selection ring, wider than the feet, may still touch the panels' edge.

@export var pitch_degrees: float = 50.0
@export var distance: float = 12.0
@export var min_distance: float = 8.0
@export var max_distance: float = 18.0
@export var zoom_step: float = 1.0
## Radians per second while a rotate key is held.
@export var rotate_speed: float = 1.6
@export var follow_sharpness: float = 8.0
## The margin from the walls at the screen's left and right, as a fraction of the view's half-width.
@export var side_fraction: float = 0.85
## The margin from the wall at the screen's bottom, as a fraction of the view's reach toward the camera:
## under 1, so a unit at that wall stands clear of the gift bar along the screen's bottom edge.
@export var near_fraction: float = 0.8
## The margin from the wall at the screen's top, as a fraction of the view's reach toward the camera.
@export var far_fraction: float = 0.5
## How far in from the screen's left edge, in the viewport's pixels, the feet of a unit at the wall on
## that side are drawn at least: about the party panels' width. At 0 that wall is held like the right
## one.
@export var panel_reserve_px: float = 0.0

var target: Node3D
## The room's floor in world x and z (a `Rect2`'s y is z); without area the focus is not held in.
var _bounds: Rect2 = Rect2()


func _ready() -> void:
	_place_camera()


# In the physics step, where units move: followed once per frame instead, the focus would chase a
# target that moves on some frames and not on others, and the target would shake on screen.
func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var weight: float = 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(focus_for(target.global_position), weight)


## Holds the focus point inside `floor_rect` (world x and z) shrunk by the margins, from now on, as
## `Room.floor_bounds()` gives it. A rectangle without area lets the focus go anywhere.
func set_bounds(floor_rect: Rect2) -> void:
	_bounds = floor_rect


## Where the rig looks when its target stands at `point`: the point itself, or the nearest point inside
## the room's floor shrunk by the margins (its middle, along an axis where the floor is narrower than
## two margins).
func focus_for(point: Vector3) -> Vector3:
	if not _bounds.has_area():
		return point
	var lo: Vector2 = _bounds.position + Vector2(margin_toward(Vector2.LEFT), margin_toward(Vector2.UP))
	var hi: Vector2 = _bounds.end - Vector2(margin_toward(Vector2.RIGHT), margin_toward(Vector2.DOWN))
	var middle: Vector2 = _bounds.get_center()
	return Vector3(
			clampf(point.x, lo.x, hi.x) if lo.x <= hi.x else middle.x,
			point.y,
			clampf(point.z, lo.y, hi.y) if lo.y <= hi.y else middle.y)


## How far the focus keeps from a wall whose side facing away from the room is `outward` (world x and
## z, a `Vector2`'s y is z), for the way the camera is turned and zoomed. Between quarter turns the
## margins blend.
func margin_toward(outward: Vector2) -> float:
	var reach: Vector2 = view_reach()
	# Where the camera looks, along the floor: -z unturned.
	var look := Vector2(-sin(rotation.y), -cos(rotation.y))
	# To the screen's right, along the floor: +x unturned.
	var right := Vector2(cos(rotation.y), -sin(rotation.y))
	var ahead: float = outward.normalized().dot(look)
	var depth: float = (far_fraction if ahead > 0.0 else near_fraction) * reach.y
	var side: float = _left_fraction() if outward.normalized().dot(right) < 0.0 else side_fraction
	return (1.0 - absf(ahead)) * side * reach.x + absf(ahead) * depth


## How far the view reaches on the floor from the focus point: across the screen to its side edge (x),
## and toward the camera to its bottom edge (y), in metres.
func view_reach() -> Vector2:
	var cam: Camera3D = camera()
	var half_fov: float = deg_to_rad(cam.fov) / 2.0
	var view: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = view.x / view.y if view.y > 0.0 else 1.0
	var pitch: float = deg_to_rad(pitch_degrees)
	var across: float = distance * tan(half_fov) * aspect
	# Past straight down the bottom edge would look back toward the camera; hold it just short.
	var lowest: float = minf(pitch + half_fov, deg_to_rad(89.0))
	var toward: float = distance * cos(pitch) - distance * sin(pitch) / tan(lowest)
	return Vector2(across, toward)


## The margin from the wall at the screen's left, as a fraction of the view's half-width: the side
## fraction, or less, so that a unit at that wall stands `panel_reserve_px` in from the screen's edge.
func _left_fraction() -> float:
	if panel_reserve_px <= 0.0:
		return side_fraction
	var half_width: float = get_viewport().get_visible_rect().size.x / 2.0
	if half_width <= 0.0:
		return side_fraction
	return clampf(1.0 - panel_reserve_px / half_width, 0.0, side_fraction)


func rotate_by(radians: float) -> void:
	rotation.y += radians


## Positive steps zoom out.
func zoom_by(steps: int) -> void:
	distance = clampf(distance + steps * zoom_step, min_distance, max_distance)
	_place_camera()


func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = focus_for(target.global_position)
	_place_camera()


func camera() -> Camera3D:
	return $Camera


## Places the camera `distance` back along the pitched arm, looking at the rig origin.
func _place_camera() -> void:
	var pitch: float = deg_to_rad(pitch_degrees)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	camera().transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)
