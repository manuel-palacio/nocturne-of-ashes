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
