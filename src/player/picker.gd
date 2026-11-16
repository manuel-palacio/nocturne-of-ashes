class_name Picker
extends RefCounted
## Finds what lies under a screen point: a unit, or the ground. Neither ray tests the "walls" layer (3):
## the wall nearest the camera is not drawn, and its collider must not catch clicks meant for the room.

## Length of a pick ray, in metres.
const _RAY_LENGTH: float = 100.0
const _WORLD_MASK: int = 0b001
const _UNITS_MASK: int = 0b010


## The first body on the "units" layer (2) under `screen`, or null.
static func unit_at(camera: Camera3D, screen: Vector2) -> Unit:
	var hit: Dictionary = _cast(camera, screen, _UNITS_MASK)
	return null if hit.is_empty() else hit.collider as Unit


## The point on the "world" layer (1) under `screen`, else where the ray meets the plane Y = 0,
## else null.
static func ground_at(camera: Camera3D, screen: Vector2) -> Variant:
	var hit: Dictionary = _cast(camera, screen, _WORLD_MASK)
	if not hit.is_empty():
		return hit.position
	# Past the walls nothing is hit; the ground plane still gives a point.
	return Plane(Vector3.UP, 0.0).intersects_ray(
		camera.project_ray_origin(screen), camera.project_ray_normal(screen))


static func _cast(camera: Camera3D, screen: Vector2, mask: int) -> Dictionary:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * _RAY_LENGTH, mask)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)
