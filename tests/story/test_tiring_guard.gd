# tests/story/test_tiring_guard.gd
extends GutTest
## Nobody is walled in by the vault: from the third fall in the same room on, each fall leaves the guard
## there with 10% less health than the last, down to 70% of its tuned health, and the re-entry says the
## guard is tiring. The count lives in `Main` for the session: a fall's reload keeps it, clearing the
## room or leaving it forgets it, and nothing of it goes into the save.

var main: Main


func after_each() -> void:
	Story.finish(main)


func _boot() -> void:
	main = Story.boot(self, PageBoot.haven_finished())
	await wait_physics_frames(3)


## Álvar falls and the fall prompt is answered: the checkpoint at the vault's entry is reloaded.
func _fall_and_get_up() -> void:
	main.player.take_hit(9999)
	await wait_physics_frames(2)
	assert_false(main.player.is_alive())
	main.reload_checkpoint()
	await wait_physics_frames(3)


## Each enemy's maximum health as a percentage of its scene's, rounded.
func _guard_shares() -> Array[int]:
	var shares: Array[int] = []
	for enemy: Unit in main.enemies:
		var scene: PackedScene = Encounter.SERGEANT if enemy.display_name == "Sergeant" else Encounter.CRUSADER
		var tuned: Unit = scene.instantiate()
		shares.append(roundi(100.0 * enemy.stats.max_health / tuned.stats.max_health))
		tuned.free()
	return shares


func _all(percent: int) -> Array[int]:
	var all: Array[int] = []
	all.resize(6)
	all.fill(percent)
	return all


func test_the_first_two_falls_leave_the_guard_whole() -> void:
	await _boot()
	assert_eq(_guard_shares(), _all(100))
	for fall: int in 2:
		await _fall_and_get_up()
		assert_eq(main.room.room_id, &"vault")
		assert_eq(_guard_shares(), _all(100), "after fall %d" % (fall + 1))
		assert_ne(main.hud.notice(), "The guard is tiring.")


func test_from_the_third_fall_the_guard_tires_by_a_tenth_down_to_seven_tenths() -> void:
	await _boot()
	var expected: Array[int] = [100, 100, 90, 80, 70, 70]
	for fall: int in expected.size():
		await _fall_and_get_up()
		assert_eq(_guard_shares(), _all(expected[fall]), "after fall %d" % (fall + 1))
		for enemy: Unit in main.enemies:
			assert_eq(enemy.stats.health, enemy.stats.max_health, "whole at its tired strength")
		if expected[fall] < 100:
			assert_eq(main.hud.notice(), "The guard is tiring.", "said on re-entry after fall %d" % (fall + 1))


func test_the_tiring_notice_reads_in_spanish() -> void:
	await _boot()
	for fall: int in 3:
		await _fall_and_get_up()
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq((main.hud.find_child("NoticeLabel") as Label).text, "La guardia se cansa.")
	TranslationServer.set_locale("en")
	await wait_physics_frames(2)


func test_clearing_the_room_forgets_the_falls() -> void:
	await _boot()
	for fall: int in 3:
		await _fall_and_get_up()
	assert_eq(_guard_shares(), _all(90))
	for enemy: Unit in main.enemies:
		enemy.take_hit(99999)
	await wait_physics_frames(3)
	assert_true(main.is_cleared())
	assert_eq(main.guard_health(), 1.0, "a cleared room starts its count again")


func test_leaving_the_room_forgets_the_falls() -> void:
	await _boot()
	for fall: int in 3:
		await _fall_and_get_up()
	assert_eq(_guard_shares(), _all(90))
	# Nobody near Álvar at the vault's entry: the west door lets the party through.
	(main.room.find_child("WestDoor") as Door).use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	(main.room.find_child("StairDoor") as Door).use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(_guard_shares(), _all(100), "the guard whole again")
	assert_ne(main.hud.notice(), "The guard is tiring.")
	await _fall_and_get_up()
	assert_eq(_guard_shares(), _all(100), "the count began again: this is the first fall")


func test_the_count_is_not_saved() -> void:
	await _boot()
	var saved_before: Dictionary = main.store.load_state().to_dict()
	for fall: int in 3:
		await _fall_and_get_up()
	assert_eq(_guard_shares(), _all(90))
	assert_eq(main.store.load_state().to_dict(), saved_before, "the save is the vault's entry, as it was")
	assert_eq(main.state.to_dict().keys(), saved_before.keys(), "no new field in the state")
