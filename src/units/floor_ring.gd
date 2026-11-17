class_name FloorRing
extends MeshInstance3D
## A thin flat ring lying just above the floor, edged dark on both sides so it reads on a pale floor as
## on a dark one. Unshaded and casting no shadow, it looks the same in light and in the dark. Rings of
## one size and colour share their mesh, and every mark shares one material (`marks_material()`), so
## the marks add a single shader to compile.

## How far above its parent's origin, the floor where a figure stands, it lies: clear of the floor's
## surface, so the two never fight for the same pixels.
const LIFT: float = 0.04
## The width of the dark edge on each side, in metres.
const EDGE: float = 0.012
const EDGE_COLOUR: Color = Color(0.05, 0.04, 0.03)
const SEGMENTS: int = 40

static var _meshes: Dictionary = {}  # String -> ArrayMesh
static var _material: StandardMaterial3D


## A ring of outer `radius`, its coloured band `width` wide.
func _init(radius: float = 0.5, width: float = 0.04, colour: Color = Color.WHITE) -> void:
	mesh = _ring(radius, width, colour)
	material_override = marks_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = LIFT


## The material of every mark: unshaded, its colours from the mesh's vertices, back faces culled.
static func marks_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
	return _material


## Three bands from the outside in: dark edge, colour, dark edge, as one flat mesh facing up.
static func _ring(radius: float, width: float, colour: Color) -> ArrayMesh:
	var key: String = "%s/%s/%s" % [radius, width, colour.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var radii: Array[float] = [radius, radius - EDGE, radius - EDGE - width, radius - 2.0 * EDGE - width]
	var colours: Array[Color] = [EDGE_COLOUR, colour, EDGE_COLOUR]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for band: int in 3:
		tool.set_color(colours[band])
		for i: int in SEGMENTS:
			var a: float = TAU * i / SEGMENTS
			var b: float = TAU * (i + 1) / SEGMENTS
			var outer_a := Vector3(cos(a), 0.0, sin(a)) * radii[band]
			var outer_b := Vector3(cos(b), 0.0, sin(b)) * radii[band]
			var inner_a := Vector3(cos(a), 0.0, sin(a)) * radii[band + 1]
			var inner_b := Vector3(cos(b), 0.0, sin(b)) * radii[band + 1]
			for corner: Vector3 in [outer_a, inner_b, inner_a, outer_a, outer_b, inner_b]:
				tool.add_vertex(corner)
	var ring: ArrayMesh = tool.commit()
	_meshes[key] = ring
	return ring
