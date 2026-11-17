extends GutTest

var arena: Arena
var alvar: Unit
var thing: Interactable

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	thing = arena.add_interactable(Vector3(0, 0, 6))
	await wait_physics_frames(3)

func test_an_interact_order_walks_up_and_uses_it() -> void:
	watch_signals(thing)
	watch_signals(alvar)
	alvar.order_interact(thing)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)
	await wait_for_signal(thing.used, 5.0)
	assert_signal_emitted_with_parameters(thing, "used", [alvar])
	assert_signal_emitted_with_parameters(alvar, "interacted", [thing])
	assert_lt(Arena.flat(alvar.global_position, thing.global_position), 2.2)
	assert_gt(Arena.flat(alvar.global_position, thing.global_position), 1.0)
	await wait_physics_frames(2)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_already_in_reach_it_is_used_at_once() -> void:
	alvar.global_position = Vector3(0, 0, 4.5)
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(3)
	assert_signal_emit_count(thing, "used", 1)

func test_a_new_order_breaks_it_off() -> void:
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(5)
	alvar.order_move(Vector3(-4, 0, 0))
	await wait_seconds(2.5)
	assert_signal_not_emitted(thing, "used")

func test_a_target_freed_on_the_way_ends_the_order() -> void:
	alvar.order_interact(thing)
	await wait_physics_frames(5)
	thing.free()
	await wait_physics_frames(5)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_the_fury_ignores_interact_orders() -> void:
	alvar.stats.spend_blood(55)
	await wait_physics_frames(3)
	alvar.order_interact(thing)
	assert_ne(alvar.current_order(), Unit.Order.INTERACT)

func test_a_stunned_unit_keeps_the_order_and_finishes_it() -> void:
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 0.5
	stun.stuns = true
	alvar.add_effect(stun)
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_for_signal(thing.used, 6.0)
	assert_signal_emit_count(thing, "used", 1)

func test_brains_and_the_fury_do_not_see_interactables() -> void:
	assert_false(thing.is_in_group(&"units"))

func test_the_picker_finds_it_and_a_click_orders_the_interaction() -> void:
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	arena.room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	var input := PlayerInput.new()
	arena.room.add_child(input)
	input.unit = alvar
	input.rig = rig
	await wait_physics_frames(2)
	var at: Vector2 = cam.unproject_position(thing.global_position + Vector3(0, 0.9, 0))
	assert_eq(Picker.interactable_at(cam, at), thing)
	input.click_at(at)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)

func test_one_that_refuses_is_not_approached() -> void:
	var picky := arena.add_interactable(Vector3(-6, 0, 0), func(_u: Unit) -> bool: return false)
	alvar.order_interact(picky)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_target_that_starts_refusing_on_the_way_is_left_alone() -> void:
	var open: Array[bool] = [true]
	var door := arena.add_interactable(Vector3(-6, 0, 0), func(_u: Unit) -> bool: return open[0])
	watch_signals(door)
	watch_signals(alvar)
	alvar.order_interact(door)
	await wait_physics_frames(10)
	open[0] = false
	await wait_physics_frames(3)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_false(alvar.is_moving())
	await wait_seconds(1.5)
	assert_signal_not_emitted(door, "used")
	assert_signal_not_emitted(alvar, "interacted")
	assert_push_warning_count(0)

func test_one_that_refuses_at_the_moment_of_use_gives_no_interacted() -> void:
	var grudging := Grudging.new()
	arena.room.add_child(grudging)
	grudging.global_position = Vector3(0, 0, 3)
	watch_signals(grudging)
	watch_signals(alvar)
	alvar.order_interact(grudging)
	await wait_seconds(1.5)
	assert_eq(grudging.tries, 1)
	assert_signal_not_emitted(grudging, "used")
	assert_signal_not_emitted(alvar, "interacted")
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_subclass_that_skips_super_stays_on_the_interact_layer() -> void:
	var odd := NoSuper.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	odd.add_child(shape)
	arena.room.add_child(odd)
	odd.global_position = Vector3(-3, 0, 3)
	assert_eq(odd.collision_layer, 0b1000)
	assert_eq(odd.collision_mask, 0)
	var cam: Camera3D = await _camera_on_alvar()
	var at: Vector2 = cam.unproject_position(odd.global_position + Vector3(0, 0.9, 0))
	assert_eq(Picker.interactable_at(cam, at), odd)

func test_a_target_out_of_reach_of_the_floor_ends_the_order_quietly() -> void:
	var far := arena.add_interactable(Vector3(0, 0, 15))
	watch_signals(far)
	watch_signals(alvar)
	alvar.order_interact(far)
	await wait_until(func() -> bool: return alvar.current_order() == Unit.Order.NONE, 6.0)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_gt(alvar.global_position.z, 8.0)
	assert_signal_not_emitted(far, "used")
	assert_signal_not_emitted(alvar, "interacted")
	assert_push_warning_count(0)

func test_an_interact_order_breaks_a_feed_and_proceeds() -> void:
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, -1.2))
	await wait_physics_frames(3)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	assert_true(alvar.is_feeding())
	watch_signals(alvar)
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(3)
	assert_signal_emitted(alvar, "feed_broken")
	assert_false(alvar.is_feeding())
	assert_false(foe.is_stunned())
	assert_true(foe.is_alive())
	assert_eq(alvar.stats.blood, 60)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)
	await wait_for_signal(thing.used, 5.0)
	assert_signal_emit_count(thing, "used", 1)

func test_a_target_freed_during_a_stun_ends_the_order_after_it() -> void:
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	alvar.add_effect(stun)
	alvar.order_interact(thing)
	await wait_physics_frames(5)
	thing.free()
	await wait_physics_frames(5)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)
	await wait_seconds(1.3)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_engine_error_count(0)
	assert_push_error_count(0)

func test_within_reach_while_processing_is_off_it_waits_to_use_it() -> void:
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(2)
	arena.room.process_mode = Node.PROCESS_MODE_DISABLED
	alvar.global_position = Vector3(0, 0, 4.5)
	await wait_physics_frames(5)
	assert_signal_not_emitted(thing, "used")
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)
	arena.room.process_mode = Node.PROCESS_MODE_INHERIT
	await wait_physics_frames(3)
	assert_signal_emit_count(thing, "used", 1)


func test_a_click_on_one_the_unit_may_not_use_gives_no_order() -> void:
	var picky := arena.add_interactable(Vector3(-5, 0, 3), func(_u: Unit) -> bool: return false)
	var cam: Camera3D = await _camera_on_alvar()
	var input := PlayerInput.new()
	arena.room.add_child(input)
	input.rig = cam.get_parent() as CameraRig
	input.unit = alvar
	var at: Vector2 = cam.unproject_position(picky.global_position + Vector3(0, 0.9, 0))
	assert_eq(Picker.interactable_at(cam, at), picky)
	input.click_at(at)
	assert_eq(alvar.current_order(), Unit.Order.NONE)


func _camera_on_alvar() -> Camera3D:
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	arena.room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	await wait_physics_frames(2)
	return cam


## Allows anyone, but its use always fails, as a door that locks at the last moment.
class Grudging extends Interactable:
	var tries: int = 0

	func use(_by: Unit) -> bool:
		tries += 1
		return false


## Defines its own `_init` without calling `super()`.
class NoSuper extends Interactable:
	func _init() -> void:
		label = "odd"
