# tests/visual/test_loose_ends.gd
extends GutTest
## Small fixes carried through milestone 4, one or two tests each.

var arena: Arena


func before_each() -> void:
	arena = Arena.new(self)


## A rig following `target`, as `Main` sets one up.
func _rig_on(target: Node3D) -> CameraRig:
	var rig := CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	add_child_autofree(rig)
	rig.target = target
	rig.snap_to_target()
	return rig

# 1. The camera follows a walking unit without jitter.

func test_the_cameras_distance_to_a_walking_unit_changes_smoothly() -> void:
	# Along the fixture's floor, 18 m in a line.
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3(-9, 0, -5))
	var rig: CameraRig = _rig_on(alvar)
	await wait_physics_frames(3)
	var goal := Vector3(9, 0, -5)
	alvar.order_move(goal)
	# Up to speed, and the follow's lag settled.
	await wait_seconds(0.5)
	var gaps: Array[float] = []
	# Sampled until it slows down to stop.
	while gaps.size() < 90 and Arena.flat(alvar.global_position, goal) > 2.0:
		await wait_process_frames(1)
		# How far the unit stands from the point the camera looks at, which is what the eye follows.
		gaps.append(Arena.flat(rig.global_position, alvar.global_position))
	assert_gt(gaps.size(), 30, "frames sampled while it walked")
	# How far the unit walks in one physics step.
	var step: float = alvar.walk_speed() / Engine.physics_ticks_per_second
	var worst: float = 0.0
	for i: int in range(1, gaps.size()):
		worst = maxf(worst, absf(gaps[i] - gaps[i - 1]))
	assert_lt(worst, step * 0.2, "the largest change of the distance in one frame, %.4f m (a step is %.4f m)" % [worst, step])

# 3. The mover re-measures the height between the feet and the navmesh along the walk.

## A static box of `size` centred at `centre`, turned by `roll` radians about z, under `parent`.
func _box(parent: Node, centre: Vector3, size: Vector3, roll: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(Basis(Vector3.BACK, roll), centre)
	parent.add_child(body)


## A floor at 0 from x = −10 to 0, a ramp up to 0.4 m from x = 0 to 3, and a floor at 0.4 m from x = 3 to
## 10, 6 m deep, its navmesh baked from its colliders.
func _stepped_floor() -> Node3D:
	var floor_root := Node3D.new()
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.agent_radius = 0.5
	region.navigation_mesh = navmesh
	floor_root.add_child(region)
	_box(region, Vector3(-5, -0.1, 0), Vector3(10, 0.2, 6))
	_box(region, Vector3(6.5, 0.2, 0), Vector3(7, 0.4, 6))
	var rise: float = atan2(0.4, 3.0)
	var length: float = Vector2(3.0, 0.4).length()
	# The ramp's top face runs from (0, 0) to (3, 0.4); the box is 0.2 thick below it.
	var down := Vector3(sin(rise), -cos(rise), 0.0) * 0.1
	_box(region, Vector3(1.5, 0.2, 0) + down, Vector3(length, 0.2, 6), rise)
	arena.room.add_child(floor_root)
	floor_root.global_position = Vector3(0, 0, 30)
	region.bake_navigation_mesh(false)
	return floor_root


## Where the navmesh lies above the feet changes along the fixture: from 0.55 m at the ramp's foot to
## 0.23 m at its top, as the bake shapes it. Walked with the height measured once per order, the walks
## from the ramp's foot up, and from its top down, end more than a path point's 0.3 m from their last
## point in 3D and stall.
func test_a_unit_walks_up_a_ramp_to_a_higher_floor_and_back() -> void:
	var floor_root: Node3D = _stepped_floor()
	var origin: Vector3 = floor_root.global_position
	var alvar: Unit = arena.spawn(Arena.ALVAR, origin + Vector3(-7, 0, 0))
	await wait_physics_frames(5)
	# Along x, with the height of the floor there.
	for x: float in [0.0, 3.0, 7.0, 3.0, 0.0, -7.0]:
		var floor_y: float = clampf(x / 3.0, 0.0, 1.0) * 0.4
		var goal: Vector3 = origin + Vector3(x, floor_y, 0)
		alvar.order_move(goal)
		await wait_for_signal(alvar.arrived, 6.0)
		var at: Vector3 = alvar.global_position - origin
		assert_lt(Arena.flat(alvar.global_position, goal), 0.5, "walked to x = %.1f, stands at %s" % [x, at])
		assert_almost_eq(at.y, floor_y, 0.05, "on the floor at x = %.1f" % x)
		assert_false(alvar.is_moving())
	assert_push_warning_count(0)

# 5. An order that waits for a landing that never comes is dropped with one warning after 5 s.

func test_an_order_given_in_a_fall_that_never_lands_warns_once_and_is_dropped() -> void:
	# Below the fixture's floor, falling with nothing under it.
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3(0, -2, -5))
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	await wait_physics_frames(3)
	alvar.order_attack(foe)
	# The target walks back and forth, so the chase is aimed again and again while it waits.
	for leg: int in 3:
		foe.order_move(Vector3(-4 if leg % 2 == 0 else 4, 0, 5))
		await wait_seconds(1.5)
	assert_false(alvar.is_on_floor())
	assert_eq(alvar.current_order(), Unit.Order.ATTACK, "still waiting before 5 s")
	assert_push_warning_count(0)
	foe.order_move(Vector3(-4, 0, 5))
	await wait_seconds(1.0)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_false(alvar.is_moving())
	assert_push_warning("could not plan its move order")
	await wait_seconds(1.0)
	assert_push_warning_count(1)
