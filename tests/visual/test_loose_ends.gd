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

