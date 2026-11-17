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

func test_walking_shows_the_walk_and_stopping_returns_to_idle() -> void:
	alvar.order_move(Vector3(-6, 0, 0))
	await wait_seconds(0.5)
	assert_eq(_visual(alvar).clip(), &"walk")
	await wait_for_signal(alvar.arrived, 4.0)
	await wait_seconds(0.3)
	assert_eq(_visual(alvar).clip(), &"idle")

func test_a_hastened_unit_runs() -> void:
	(alvar.get_node("Gifts") as GiftUser).use(0)
	await wait_seconds(0.8)  # let the cast show
	alvar.order_move(Vector3(-8, 0, 0))
	await wait_seconds(0.5)
	assert_eq(_visual(alvar).clip(), &"run")

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
	var box: AABB = AABB()
	for node: Node in _visual(foe).model().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var mesh_box: AABB = mesh.global_transform * mesh.get_aabb()
		box = mesh_box if box.size == Vector3.ZERO else box.merge(mesh_box)
	assert_lt(absf(box.position.y - foe.global_position.y), 0.3)

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
