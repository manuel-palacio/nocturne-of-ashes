# tests/visual/test_unit_visual.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func _visual(unit: Unit) -> UnitVisual:
	return unit.get_node("Visual") as UnitVisual

func test_standing_still_is_idle() -> void:
	assert_eq(_visual(alvar).clip(), &"idle")

func _player(unit: Unit) -> AnimationPlayer:
	return _visual(unit).model().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

func test_moving_shows_the_run_and_stopping_returns_to_idle() -> void:
	alvar.order_move(Vector3(-6, 0, 0))
	await wait_seconds(0.5)
	assert_eq(_visual(alvar).clip(), &"run")
	await wait_for_signal(alvar.arrived, 4.0)
	await wait_seconds(0.3)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_a_slow_unit_walks() -> void:
	alvar.move_speed = 1.5
	alvar.order_move(Vector3(-6, 0, 0))
	await wait_seconds(0.5)
	assert_eq(_visual(alvar).clip(), &"walk")

func test_a_hastened_unit_runs() -> void:
	alvar.order_move(Vector3(-8, 0, 0))
	await wait_seconds(0.5)
	var normal: float = _player(alvar).speed_scale
	alvar.stop()
	(alvar.get_node("Gifts") as GiftUser).use(0)
	await wait_seconds(0.8)  # let the cast show
	alvar.order_move(Vector3(8, 0, 0))
	await wait_seconds(0.5)
	assert_eq(_visual(alvar).clip(), &"run")
	assert_gt(_player(alvar).speed_scale, normal)

func test_a_strike_shows_the_attack() -> void:
	alvar.order_attack(foe)
	await wait_for_signal((alvar.get_node("Melee") as MeleeAttack).hit, 3.0)
	await wait_physics_frames(2)
	assert_eq(_visual(alvar).clip(), &"attack")

func test_being_hit_shows_the_hit() -> void:
	alvar.take_hit(5, foe)
	await wait_physics_frames(2)
	assert_eq(_visual(alvar).clip(), &"hit")
	await wait_seconds(0.9)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_using_a_gift_shows_the_cast() -> void:
	(alvar.get_node("Gifts") as GiftUser).use(0)
	await wait_physics_frames(2)
	assert_eq(_visual(alvar).clip(), &"cast")

func test_a_stunned_unit_staggers() -> void:
	(alvar.get_node("Gifts") as GiftUser).use(1, foe)
	await wait_physics_frames(2)
	assert_eq(_visual(foe).clip(), &"stagger")

func test_feeding_shows_on_both() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.6)
	assert_eq(_visual(alvar).clip(), &"feed")
	assert_eq(_visual(foe).clip(), &"stagger")

func test_a_fallen_unit_shows_the_death_clip() -> void:
	foe.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(_visual(foe).clip(), &"death")
	await wait_seconds(2.5)
	assert_eq(_visual(foe).clip(), &"death")
	var skeleton: Skeleton3D = _visual(foe).model().find_children("*", "Skeleton3D", true, false)[0]
	var height := func(bone: int) -> float:
		return (skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin).y - foe.global_position.y
	assert_lt(height.call(skeleton.find_bone("DEF-head")), 0.5)
	assert_lt(height.call(skeleton.find_bone("DEF-spine.002")), 0.5)
	var lowest: float = INF
	for bone: int in skeleton.get_bone_count():
		lowest = minf(lowest, height.call(bone))
	assert_gt(lowest, -0.1)

func test_dying_mid_swing_falls_at_once() -> void:
	alvar.order_attack(foe)
	await wait_for_signal((alvar.get_node("Melee") as MeleeAttack).hit, 3.0)
	alvar.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(_visual(alvar).clip(), &"death")

func test_rising_returns_to_idle() -> void:
	alvar.take_hit(999)
	await wait_seconds(0.5)
	alvar.revive()
	await wait_seconds(2.0)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_a_walking_unit_faces_where_it_goes() -> void:
	alvar.order_move(Vector3(6, 0, 0))
	await wait_seconds(0.8)
	var forward: Vector3 = -alvar.global_transform.basis.z
	assert_gt(forward.dot(Vector3(1, 0, 0)), 0.9)

func test_the_visual_never_moves_the_unit() -> void:
	var at: Vector3 = alvar.global_position
	var layer: int = alvar.collision_layer
	(alvar.get_node("Gifts") as GiftUser).use(0)
	alvar.take_hit(5, foe)
	await wait_seconds(1.0)
	assert_lt(Arena.flat(alvar.global_position, at), 0.01)
	assert_eq(alvar.collision_layer, layer)

func test_animation_holds_while_the_units_are_not_processing() -> void:
	alvar.order_move(Vector3(-6, 0, 0))
	await wait_seconds(0.4)
	arena.room.process_mode = Node.PROCESS_MODE_DISABLED
	var player: AnimationPlayer = _visual(alvar).model().find_children("*", "AnimationPlayer", true, false)[0]
	var at: float = player.current_animation_position
	await wait_seconds(0.4)
	assert_almost_eq(player.current_animation_position, at, 0.001)
	arena.room.process_mode = Node.PROCESS_MODE_INHERIT

func _bone_poses(model: Node3D) -> Array[Transform3D]:
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var poses: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(bone))
	return poses

func test_a_unit_spawned_while_held_shows_the_idle_pose() -> void:
	var held := Node3D.new()
	held.process_mode = Node.PROCESS_MODE_DISABLED
	arena.room.add_child(held)
	var zahra: Unit = Arena.ZAHRA.instantiate()
	var brain: Node = zahra.get_node("Brain")
	zahra.remove_child(brain)
	brain.free()
	held.add_child(zahra)
	await wait_physics_frames(3)
	var reference: Node3D = add_child_autofree(UnitVisual.HUMAN.instantiate())
	var player: AnimationPlayer = reference.find_children("*", "AnimationPlayer", true, false)[0]
	player.play(&"idle")
	player.advance(0.0)
	var skeleton: Skeleton3D = reference.find_children("*", "Skeleton3D", true, false)[0]
	var shown: Array[Transform3D] = _bone_poses(_visual(zahra).model())
	var idle: Array[Transform3D] = _bone_poses(reference)
	var moved_from_rest: int = 0
	for bone: int in shown.size():
		assert_true(shown[bone].is_equal_approx(idle[bone]), skeleton.get_bone_name(bone))
		if not shown[bone].is_equal_approx(skeleton.get_bone_rest(bone)):
			moved_from_rest += 1
	assert_gt(moved_from_rest, 0)

func test_a_nudged_unit_stays_idle() -> void:
	alvar.velocity = Vector3(0.1, 0, 0)
	await wait_physics_frames(3)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_a_moving_unit_keeps_travelling_down_to_the_lower_threshold() -> void:
	alvar.order_move(Vector3(-6, 0, 0))
	await wait_seconds(0.5)
	alvar.stop()
	alvar.velocity = Vector3(0.08, 0, 0)
	await wait_physics_frames(3)
	assert_true(_visual(alvar).clip() in [&"walk", &"run"], String(_visual(alvar).clip()))
	alvar.velocity = Vector3(0.03, 0, 0)
	await wait_physics_frames(3)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_walk_and_run_switch_with_a_margin() -> void:
	alvar.move_speed = 2.2
	alvar.order_move(Vector3(-8, 0, 0))
	await wait_seconds(0.4)
	assert_eq(_visual(alvar).clip(), &"walk", "2.2 m/s from a walk")
	alvar.move_speed = 4.0
	await wait_seconds(0.3)
	assert_eq(_visual(alvar).clip(), &"run", "4 m/s")
	alvar.move_speed = 2.2
	await wait_seconds(0.3)
	assert_eq(_visual(alvar).clip(), &"run", "2.2 m/s from a run")
	alvar.move_speed = 1.8
	await wait_seconds(0.3)
	assert_eq(_visual(alvar).clip(), &"walk", "1.8 m/s")

func _lean(unit: Unit) -> float:
	return _visual(unit).model().position.length()

func test_a_feeder_leans_in_while_drinking_and_back_after_the_feed() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	assert_true(alvar.is_feeding())
	assert_gt(_lean(alvar), 0.3)
	await wait_for_signal(alvar.fed, 3.0)
	await wait_seconds(1.0)
	assert_almost_eq(_lean(alvar), 0.0, 0.001)

func test_a_broken_feed_leans_back() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	assert_gt(_lean(alvar), 0.3)
	alvar.stop()
	await wait_seconds(1.0)
	assert_almost_eq(_lean(alvar), 0.0, 0.001)

func test_a_seated_speaker_talks_seated_and_sits_again() -> void:
	var npc: Npc = preload("res://scenes/rooms/npc.tscn").instantiate()
	npc.sitting = true
	arena.room.add_child(npc)
	npc.global_position = Vector3(4, 0, 0)
	await wait_physics_frames(2)
	var visual: UnitVisual = npc.get_node("Visual")
	assert_eq(visual.clip(), &"sit")
	npc.set_speaking(true)
	await wait_physics_frames(2)
	assert_eq(visual.clip(), &"sit_talk")
	npc.set_speaking(false)
	await wait_physics_frames(2)
	assert_eq(visual.clip(), &"sit")
