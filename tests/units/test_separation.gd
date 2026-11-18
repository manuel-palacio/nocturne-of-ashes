extends GutTest
## Units keep a little apart: a gentle push between living units closer than a body's width, which
## moves nobody through a wall, never parts a feeder from its meal and never stops an order.

var arena: Arena


func before_each() -> void:
	arena = Arena.new(self)


func test_two_idle_units_on_one_spot_step_apart() -> void:
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	var zahra: Unit = arena.spawn(Arena.ZAHRA, Vector3.ZERO)
	watch_signals(alvar)
	watch_signals(zahra)
	await wait_seconds(2.0)
	assert_gte(Arena.flat(alvar.global_position, zahra.global_position), 0.6)
	# Nudged apart, neither walks nor arrives anywhere.
	assert_false(alvar.is_moving())
	assert_false(zahra.is_moving())
	assert_signal_not_emitted(alvar, "arrived")
	assert_signal_not_emitted(zahra, "arrived")
	assert_eq(alvar.get_node("Visual").clip(), &"idle")
	assert_eq(zahra.get_node("Visual").clip(), &"idle")


func test_three_attackers_stand_apart_around_one_target_and_keep_striking() -> void:
	var target: Unit = arena.spawn(Arena.SERGEANT, Vector3(0, 0, 4))
	target.stats.max_health = 5000
	target.stats.reset()
	var attackers: Array[Unit] = [
		arena.spawn(Arena.ALVAR, Vector3(-0.2, 0, 0)),
		arena.spawn(Arena.ZAHRA, Vector3(0, 0, 0)),
		arena.spawn(Arena.GONZALO, Vector3(0.2, 0, 0)),
	]
	await wait_physics_frames(3)
	for attacker: Unit in attackers:
		attacker.order_attack(target)
	await wait_seconds(3.0)
	var struck: Dictionary[Unit, int] = {}
	target.was_hit.connect(func(_amount: int, source: Unit) -> void: struck[source] = struck.get(source, 0) + 1)
	await wait_seconds(2.5)
	for i: int in attackers.size():
		var attacker: Unit = attackers[i]
		assert_eq(attacker.attack_target(), target)
		assert_gt(struck.get(attacker, 0), 0, "%s keeps striking" % attacker.name)
		for j: int in range(i + 1, attackers.size()):
			assert_gte(Arena.flat(attacker.global_position, attackers[j].global_position), 0.5)


func test_a_walk_to_where_another_stands_arrives_and_ends() -> void:
	var walker: Unit = arena.spawn(Arena.ALVAR, Vector3(-4, 0, 0))
	arena.spawn(Arena.ZAHRA, Vector3(2, 0, -3))
	await wait_physics_frames(3)
	watch_signals(walker)
	walker.order_move(Vector3(2, 0, -3))
	await wait_for_signal(walker.arrived, 5.0)
	assert_signal_emitted(walker, "arrived")
	assert_lte(Arena.flat(walker.global_position, Vector3(2, 0, -3)), 1.0)
	assert_eq(walker.current_order(), Unit.Order.NONE)
	assert_push_warning_count(0)


func test_a_feeder_and_its_meal_are_not_pushed_apart() -> void:
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	var meal: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 0.5))
	var bystander: Unit = arena.spawn(Arena.ZAHRA, Vector3(0.2, 0, 0.6))
	await wait_physics_frames(3)
	meal.take_hit(45)
	alvar.order_feed(meal)
	await wait_physics_frames(3)
	assert_true(alvar.is_feeding())
	var feeder_at: Vector3 = alvar.global_position
	var meal_at: Vector3 = meal.global_position
	await wait_seconds(1.2)
	assert_true(alvar.is_feeding())
	assert_lt(Arena.flat(alvar.global_position, feeder_at), 0.01)
	assert_lt(Arena.flat(meal.global_position, meal_at), 0.01)
	# Both still push: the bystander is the one who steps away.
	assert_gte(Arena.flat(bystander.global_position, meal.global_position), 0.6)
	assert_gte(Arena.flat(bystander.global_position, alvar.global_position), 0.6)


func test_a_unit_beside_a_wall_is_not_pushed_through_it() -> void:
	# The fixture's block spans x from 4 to 6 and z from -1 to 1; a body is 0.35 m in radius.
	var by_wall: Unit = arena.spawn(Arena.ALVAR, Vector3(3.62, 0, 0))
	var pusher: Unit = arena.spawn(Arena.ZAHRA, Vector3(3.4, 0, 0))
	await wait_seconds(1.5)
	assert_lt(by_wall.global_position.x, 3.67)
	assert_gte(Arena.flat(by_wall.global_position, pusher.global_position), 0.6)


func test_followers_settle_apart_and_a_walk_to_an_empty_spot_arrives_close() -> void:
	var leader: Unit = arena.spawn(Arena.ALVAR, Vector3(-6, 0, 6))
	var followers: Array[Unit] = [
		arena.spawn(Arena.ZAHRA, Vector3(-6.2, 0, 7.5), true),
		arena.spawn(Arena.GONZALO, Vector3(-5.8, 0, 7.5), true),
		arena.spawn(Arena.ZAHRA, Vector3(-6, 0, 7.8), true),
	]
	for follower: Unit in followers:
		(follower.get_node("Brain") as CombatBrain).leader = leader
	await wait_physics_frames(3)
	watch_signals(leader)
	leader.order_move(Vector3(2, 0, -6))
	await wait_for_signal(leader.arrived, 8.0)
	assert_signal_emitted(leader, "arrived")
	assert_lte(Arena.flat(leader.global_position, Vector3(2, 0, -6)), 0.5)
	await wait_seconds(5.0)
	var rested: Array[Vector3] = []
	for follower: Unit in followers:
		rested.append(follower.global_position)
	await wait_seconds(1.0)
	for i: int in followers.size():
		var follower: Unit = followers[i]
		assert_false(follower.is_moving(), "%s at rest" % follower.name)
		assert_lt(Arena.flat(follower.global_position, rested[i]), 0.05, "%s still" % follower.name)
		assert_lt(Arena.flat(follower.global_position, leader.global_position), 4.5)
		for j: int in range(i + 1, followers.size()):
			assert_gte(Arena.flat(follower.global_position, followers[j].global_position), 0.5)
	assert_push_warning_count(0)


func test_a_stunned_unit_stays_put_and_its_neighbour_steps_away() -> void:
	var stunned: Unit = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	var neighbour: Unit = arena.spawn(Arena.ZAHRA, Vector3(0.3, 0, 0))
	var stun := StatusEffect.new()
	stun.id = &"test_stun"
	stun.stuns = true
	stun.duration = 5.0
	stunned.add_effect(stun)
	await wait_physics_frames(3)
	var stunned_at: Vector3 = stunned.global_position
	await wait_seconds(1.5)
	assert_true(stunned.is_stunned())
	assert_lt(Arena.flat(stunned.global_position, stunned_at), 0.01)
	assert_gte(Arena.flat(neighbour.global_position, stunned.global_position), 0.8)


func test_a_walker_passes_a_unit_standing_in_its_path_at_half_speed_or_more() -> void:
	var walker: Unit = arena.spawn(Arena.ALVAR, Vector3(-4, 0, -3))
	arena.spawn(Arena.ZAHRA, Vector3(0, 0, -3))
	await wait_physics_frames(3)
	var frames: Array[int] = [0, -1, -1]
	var count := func() -> void:
		frames[0] += 1
		if frames[1] < 0 and walker.global_position.x >= -1.0:
			frames[1] = frames[0]
		if frames[2] < 0 and walker.global_position.x >= 1.0:
			frames[2] = frames[0]
	get_tree().physics_frame.connect(count)
	watch_signals(walker)
	walker.order_move(Vector3(4, 0, -3))
	await wait_for_signal(walker.arrived, 6.0)
	get_tree().physics_frame.disconnect(count)
	assert_signal_emitted(walker, "arrived")
	assert_lte(Arena.flat(walker.global_position, Vector3(4, 0, -3)), 0.5)
	assert_push_warning_count(0)
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var half: float = walker.walk_speed() * 0.5
	assert_gte(8.0 / (frames[0] * step), half, "over the whole walk")
	assert_gt(frames[2], frames[1])
	assert_gte(2.0 / ((frames[2] - frames[1]) * step), half, "past the standing unit")


func test_two_units_on_one_spot_part_the_same_way_every_time() -> void:
	var first: Array[Vector3] = await _part_a_pair()
	var second: Array[Vector3] = await _part_a_pair()
	assert_gte(Arena.flat(first[0], first[1]), 0.8)
	assert_true(first[0].is_equal_approx(second[0]), "%s then %s" % [first[0], second[0]])
	assert_true(first[1].is_equal_approx(second[1]), "%s then %s" % [first[1], second[1]])


func _part_a_pair() -> Array[Vector3]:
	var a: Unit = arena.spawn(Arena.ALVAR, Vector3(-2, 0, 2))
	var b: Unit = arena.spawn(Arena.ZAHRA, Vector3(-2, 0, 2))
	await wait_seconds(1.5)
	var parted: Array[Vector3] = [a.global_position, b.global_position]
	a.queue_free()
	b.queue_free()
	await wait_physics_frames(2)
	return parted


func test_a_fallen_unit_neither_is_pushed_nor_pushes() -> void:
	var fallen: Unit = arena.spawn(Arena.CRUSADER, Vector3.ZERO)
	var standing: Unit = arena.spawn(Arena.ZAHRA, Vector3(0.3, 0, 0))
	await wait_physics_frames(3)
	fallen.take_hit(1000)
	var fallen_at: Vector3 = fallen.global_position
	var standing_at: Vector3 = standing.global_position
	await wait_seconds(1.5)
	assert_false(fallen.is_alive())
	assert_lt(Arena.flat(fallen.global_position, fallen_at), 0.01)
	assert_lt(Arena.flat(standing.global_position, standing_at), 0.01)


func test_an_attacker_put_out_of_range_comes_back_and_strikes() -> void:
	var target: Unit = arena.spawn(Arena.SERGEANT, Vector3(0, 0, 4))
	target.stats.max_health = 5000
	target.stats.reset()
	var attacker: Unit = arena.spawn(Arena.ALVAR, Vector3(0, 0, 0))
	await wait_physics_frames(3)
	attacker.order_attack(target)
	await wait_seconds(2.0)
	assert_lte(Arena.flat(attacker.global_position, target.global_position), 1.6)
	# As a crowd might leave it: out of range, not walking, and the target where it was.
	attacker.global_position += (attacker.global_position - target.global_position).normalized()
	await wait_physics_frames(2)
	var struck: Array[int] = [0]
	target.was_hit.connect(func(_amount: int, _source: Unit) -> void: struck[0] += 1)
	await wait_seconds(2.0)
	assert_lte(Arena.flat(attacker.global_position, target.global_position), 1.6)
	assert_gt(struck[0], 0)
	assert_push_warning_count(0)


func test_a_follower_nudged_a_little_beyond_its_place_stays_and_one_far_off_walks_back() -> void:
	var leader: Unit = arena.spawn(Arena.ALVAR, Vector3(-4, 0, 4))
	var followers: Array[Unit] = [
		arena.spawn(Arena.ZAHRA, Vector3(-4.6, 0, 7.2), true),
		arena.spawn(Arena.GONZALO, Vector3(-3.4, 0, 7.2), true),
		arena.spawn(Arena.ZAHRA, Vector3(-4, 0, 7.6), true),
	]
	for follower: Unit in followers:
		(follower.get_node("Brain") as CombatBrain).leader = leader
	await wait_seconds(3.0)
	for follower: Unit in followers:
		assert_eq(follower.current_order(), Unit.Order.NONE, "%s at rest" % follower.name)
	var nudged: Unit = followers[2]
	var bearing: Vector3 = nudged.global_position - leader.global_position
	bearing.y = 0.0
	bearing = bearing.normalized()
	nudged.global_position = leader.global_position + bearing * 4.5
	for i: int in 8:
		await wait_seconds(0.25)
		assert_eq(nudged.current_order(), Unit.Order.NONE, "no order at 4.5 m")
	assert_almost_eq(Arena.flat(nudged.global_position, leader.global_position), 4.5, 0.05)
	nudged.global_position = leader.global_position + bearing * 5.5
	await wait_seconds(0.5)
	assert_true(nudged.is_moving(), "walks back from 5.5 m")
	await wait_seconds(2.5)
	assert_lt(Arena.flat(nudged.global_position, leader.global_position), 4.0)


func test_a_follow_walk_begun_behind_a_walking_leader_is_finished_after_it_stops() -> void:
	var leader: Unit = arena.spawn(Arena.ALVAR, Vector3(-4, 0, 4))
	var follower: Unit = arena.spawn(Arena.ZAHRA, Vector3(-4, 0, 4.85), true)
	(follower.get_node("Brain") as CombatBrain).leader = leader
	await wait_seconds(1.0)
	assert_eq(follower.current_order(), Unit.Order.NONE)
	# Slow enough that the brain thinks at least once while the gap is past 4 m and the leader still
	# walks, and the follow walk is still under way when the leader stops.
	leader.move_speed = 1.0
	follower.move_speed = 1.0
	leader.order_move(Vector3(-4, 0, 0.15))
	await wait_for_signal(leader.arrived, 6.0)
	# The leader stops within its arrival distance of the point, about 4.4 m from where the follower
	# stood: inside the 5 m band for a leader standing still.
	assert_eq(follower.current_order(), Unit.Order.MOVE, "the follow walk began while the leader walked")
	await wait_seconds(3.0)
	assert_eq(follower.current_order(), Unit.Order.NONE)
	assert_lte(Arena.flat(follower.global_position, leader.global_position), 4.0)
	assert_gte(Arena.flat(follower.global_position, leader.global_position), 2.5)
	assert_push_warning_count(0)


func test_a_leader_who_walks_off_and_stops_between_thinks_is_followed() -> void:
	# At full speed the gap is past 4 m for only a moment before the leader stops 4.4 m away;
	# whatever the phase of the follower's thinks, the follow walk starts.
	for run: int in 10:
		var leader: Unit = arena.spawn(Arena.ALVAR, Vector3(-4, 0, 4))
		var follower: Unit = arena.spawn(Arena.ZAHRA, Vector3(-4, 0, 5.1), true)
		var brain := follower.get_node("Brain") as CombatBrain
		brain.leader = leader
		await wait_seconds(1.0)
		assert_eq(follower.current_order(), Unit.Order.NONE, "run %d: at rest first" % run)
		brain._since_thought = run * brain.think_interval / 10.0
		leader.order_move(Vector3(-4, 0, 0.4))
		# Polled rather than awaited as a signal, so no freed unit is left watched.
		await wait_physics_frames(2)
		for frame: int in 180:
			if not leader.is_moving():
				break
			await wait_physics_frames(1)
		assert_false(leader.is_moving(), "run %d: the leader stopped" % run)
		var gap: float = Arena.flat(leader.global_position, Vector3(-4, 0, 5.1))
		assert_between(gap, 4.2, 4.6, "run %d: the leader stops about 4.4 m away" % run)
		await wait_seconds(2.0)
		assert_lte(Arena.flat(follower.global_position, leader.global_position), 4.0, "run %d: followed" % run)
		leader.queue_free()
		follower.queue_free()
		await wait_physics_frames(2)
	assert_push_warning_count(0)
