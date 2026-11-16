# tests/units/test_order_issuer.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3(-8, 0, -8))
	foe = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 8), true)
	await wait_physics_frames(3)

func test_no_order_has_no_issuer() -> void:
	assert_eq(alvar.order_issuer(), Unit.Issuer.NONE)

func test_orders_are_the_players_unless_said_otherwise() -> void:
	alvar.order_move(Vector3(-4, 0, -8))
	assert_eq(alvar.order_issuer(), Unit.Issuer.PLAYER)
	alvar.order_move(Vector3(-4, 0, -8), Unit.Issuer.BRAIN)
	assert_eq(alvar.order_issuer(), Unit.Issuer.BRAIN)
	alvar.stop()
	assert_eq(alvar.order_issuer(), Unit.Issuer.NONE)

func test_the_issuer_clears_when_the_order_ends() -> void:
	alvar.order_move(Vector3(-6, 0, -8))
	await wait_for_signal(alvar.arrived, 4.0)
	assert_eq(alvar.order_issuer(), Unit.Issuer.NONE)

func test_a_brains_attack_is_marked_as_the_brains() -> void:
	alvar.global_position = Vector3(4, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	assert_eq(foe.order_issuer(), Unit.Issuer.BRAIN)

func test_a_players_move_during_a_follow_walk_is_left_alone() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = foe
	await wait_seconds(0.8)
	assert_eq(friend.order_issuer(), Unit.Issuer.BRAIN)
	friend.order_move(Vector3(-8, 0, 2))
	alvar.global_position = Vector3(-6, 0, 6)  # a hostile well inside aggro
	await wait_seconds(0.6)
	assert_eq(friend.order_issuer(), Unit.Issuer.PLAYER)
	assert_eq(friend.current_order(), Unit.Order.MOVE)
	assert_null(friend.attack_target())

func test_the_fury_orders_as_the_system_and_refuses_the_rest() -> void:
	alvar.global_position = Vector3(6, 0, 8)
	(foe.get_node("Brain") as CombatBrain).enabled = false
	await wait_physics_frames(2)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	assert_eq(alvar.order_issuer(), Unit.Issuer.SYSTEM)
	alvar.order_move(Vector3(-8, 0, -8))
	alvar.order_move(Vector3(-8, 0, -8), Unit.Issuer.BRAIN)
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	assert_eq(alvar.order_issuer(), Unit.Issuer.SYSTEM)

func test_a_brains_attack_stays_the_brains_across_a_switch_off_and_on() -> void:
	alvar.global_position = Vector3(4, 0, 8)
	await wait_seconds(0.6)
	var brain := foe.get_node("Brain") as CombatBrain
	brain.enabled = false
	brain.enabled = true
	assert_eq(foe.attack_target(), alvar)
	assert_eq(foe.order_issuer(), Unit.Issuer.BRAIN)

func test_every_unit_scene_has_orders_before_its_brain() -> void:
	assert_not_null(foe.get_node_or_null(^"Orders") as Orders)
	assert_lt(foe.get_node(^"Orders").get_index(), foe.get_node(^"Brain").get_index())
