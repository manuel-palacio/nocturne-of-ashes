# tests/units/test_mover.gd
extends GutTest
## The Mover on its own: frames in which the unit does not walk never count towards a stall.

var arena: Arena
var alvar: Unit
var mover: Mover

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	mover = alvar.get_node(^"Mover")
	await wait_physics_frames(3)

func test_frames_without_steering_neither_stall_nor_end_the_walk() -> void:
	alvar.order_move(Vector3(0, 0, 6))
	await wait_physics_frames(5)
	# Frozen: the unit no longer steers or moves, but the Mover still sees every frame.
	alvar.set_physics_process(false)
	var delta: float = 1.0 / Engine.physics_ticks_per_second
	for i: int in range(int(1.5 / delta)):
		mover.after_move(delta, true)
		await wait_physics_frames(1)
	assert_push_warning_count(0)
	assert_true(mover.is_walking())
	alvar.set_physics_process(true)
	await wait_for_signal(alvar.arrived, 4.0)
	assert_lt(Arena.flat(alvar.global_position, Vector3(0, 0, 6)), 0.5)
	assert_false(mover.is_walking())
