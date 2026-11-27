# tests/story/test_hints.gd
extends GutTest
## The fight's rules are taught when they first apply: each hint shows once, at its moment and not
## before, never over a conversation, a card or the fall prompt, waits while another notice is up, is
## dropped when its moment passes before it could show, and is remembered across a fall and a reload;
## a new game starts them afresh, and the skirmish shows them once per page load. A whole vault fight
## played by the scripted player shows each at most once and never two within `Hints.GAP`.

const HAVEN := preload("res://dialogue/haven.dialogue")
const SKIRMISH := preload("res://scenes/main.tscn")
const GAME := preload("res://scenes/game.tscn")

var main: Main


func after_each() -> void:
	VaultFight.slow_down()
	Story.finish(main)


## The story at the vault's door, every hint already seen but those in `unseen`.
func _vault(unseen: Array[StringName], state: GameState = null) -> void:
	if state == null:
		state = PageBoot.haven_finished()
	for id: StringName in Hints.ORDER:
		if not unseen.has(id):
			state.set_flag(Hints.flag(id))
	main = Story.boot(self, state)
	await wait_physics_frames(3)


func _hints() -> Hints:
	return main.find_child("Hints") as Hints


## The notice on show as the player reads it.
func _shown_text() -> String:
	var label := main.hud.find_child("NoticeLabel") as Label
	return label.text if label.visible else ""


func _sergeant() -> Unit:
	for enemy: Unit in main.enemies:
		if Encounter.is_sergeant(enemy):
			return enemy
	return null


func _crusader() -> Unit:
	for enemy: Unit in main.enemies:
		if not Encounter.is_sergeant(enemy):
			return enemy
	return null


## Brings `unit`'s Blood to `blood`, without crossing into the Fury unless asked.
func _set_blood(unit: Unit, blood: int) -> void:
	if blood < unit.stats.blood:
		unit.stats.spend_blood(unit.stats.blood - blood)
	else:
		unit.stats.gain_blood(blood - unit.stats.blood)


func _open_controls() -> void:
	main.hud.find_child("ControlsButton").pressed.emit()
	await wait_physics_frames(2)


# --- Each at its moment, and not before ---

func test_the_pause_hint_shows_on_entering_the_vault_and_not_in_the_haven() -> void:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	main = Story.boot(self, state)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "", "nothing to teach in the haven")
	Story.finish(main)
	main.queue_free()
	await _vault([&"pause"])
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"pause"])
	assert_true(main.state.has_flag(Hints.flag(&"pause")))


func test_the_rites_hint_shows_four_seconds_into_the_fight() -> void:
	await _vault([&"rites"])
	await wait_seconds(1.0)
	assert_eq(main.hud.notice(), "", "not before the first blow")
	_crusader().take_hit(1)
	await wait_seconds(3.0)
	assert_eq(main.hud.notice(), "", "not before four seconds")
	await wait_until(func() -> bool: return main.hud.notice() == Hints.TEXTS[&"rites"], 2.5)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"rites"])


func test_a_rite_used_before_its_moment_needs_no_hint() -> void:
	await _vault([&"rites"])
	_crusader().take_hit(1)
	await wait_physics_frames(5)
	main.input.press_gift(0)
	await wait_seconds(5.0)
	assert_eq(main.hud.notice(), "")
	assert_true(main.state.has_flag(Hints.flag(&"rites")), "learned without it")


func test_the_feed_hint_shows_once_an_enemy_is_marked() -> void:
	await _vault([&"feed"])
	var crusader: Unit = _crusader()
	crusader.take_hit(1)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "", "not before anyone is marked")
	crusader.take_hit(crusader.stats.health - crusader.stats.max_health / 2 + 1)
	await wait_physics_frames(3)
	assert_true(crusader.has_feed_mark())
	assert_eq(main.hud.notice(), Hints.TEXTS[&"feed"])


## A spam clicker feeds by accident before the hint could show: the feed does not count as the lesson,
## and the hint comes as soon as it may, to explain what just happened, though no one is marked by then.
func test_a_feed_before_the_feeding_hint_brings_the_hint() -> void:
	await _vault([&"feed"])
	main.hud.show_notice(Main.TIRING_NOTICE, [], 60.0)
	var meal: Unit = _crusader()
	meal.get_node("Brain").queue_free()
	meal.global_position = main.player.global_position + Vector3(1.5, 0.0, 0.0)
	meal.take_hit(meal.stats.health - meal.stats.max_health / 2 + 1)
	_set_blood(main.player, 60)
	main.rig.snap_to_target()
	await wait_physics_frames(3)
	assert_true(meal.has_feed_mark())
	var fed: Array[Unit] = []
	main.player.fed.connect(func(target: Unit) -> void: fed.append(target))
	main.input.click_at(main.rig.camera().unproject_position(meal.global_position + Vector3.UP * 0.9))
	await wait_until(func() -> bool: return not fed.is_empty(), 5.0)
	assert_eq(fed.size(), 1, "Álvar fed")
	assert_false(main.state.has_flag(Hints.flag(&"feed")), "a feed is not the lesson learned")
	meal.take_hit(Arena.LETHAL)
	assert_false(main.enemies.any(func(enemy: Unit) -> bool: return enemy.has_feed_mark()), "no one marked")
	main.hud.hide_notice()
	await wait_until(func() -> bool: return main.hud.notice() == Hints.TEXTS[&"feed"], 1.0)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"feed"])


func test_the_sergeant_hint_shows_when_a_sergeant_closes_in_during_a_fight() -> void:
	await _vault([&"sergeant"])
	var sergeant: Unit = _sergeant()
	var gap: Vector3 = sergeant.global_position - main.player.global_position
	assert_gt(Vector2(gap.x, gap.z).length(), Hints.SERGEANT_NEAR, "the sergeants start further off")
	sergeant.global_position = main.player.global_position + Vector3(4.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), "", "not before a blow lands")
	_crusader().take_hit(1)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"sergeant"])


func test_the_running_dry_hint_names_who_is_running_dry() -> void:
	await _vault([&"dry"])
	_set_blood(main.player, 34)
	await wait_physics_frames(5)
	assert_eq(main.hud.notice(), "", "a third is not under a third")
	_set_blood(main.player, 20)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])
	assert_eq(_shown_text(), "Brother Álvar is running dry. Feed, or the Fury will choose for you.")


## The companions' brains spend their Blood and feed on their own: running dry is Álvar's alone.
func test_running_dry_is_about_alvar_only() -> void:
	await _vault([&"dry"])
	var gonzalo: Unit = main.party[2]
	assert_eq(gonzalo.member_id, &"gonzalo")
	_set_blood(gonzalo, 30)
	_set_blood(main.party[1], 30)
	_set_blood(main.player, 60)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "", "nothing to say of a companion's Blood")
	assert_false(main.state.has_flag(Hints.flag(&"dry")))


## "Feed" is not said before the feeding hint has said how: running dry waits its turn after it.
func test_running_dry_comes_after_the_feeding_hint() -> void:
	await _vault([&"dry", &"feed"])
	_set_blood(main.player, 20)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"feed"], "feeding first, though no one is marked")
	await wait_until(func() -> bool: return main.hud.notice() == Hints.TEXTS[&"dry"], Hints.GAP + 1.0)
	assert_eq(_shown_text(), "Brother Álvar is running dry. Feed, or the Fury will choose for you.")


func test_the_fury_hint_names_whom_the_fury_has() -> void:
	await _vault([&"fury"])
	var zahra: Unit = main.party[1]
	_set_blood(zahra, 5)
	await wait_physics_frames(3)
	assert_true(zahra.is_in_fury())
	assert_eq(_shown_text(), "The Fury has Zahra. It ends when the hunger is fed or burns out.")


## Under half his health, while there is still time to walk to the door.
func test_the_door_hint_shows_when_alvar_is_down_to_half_in_a_fight() -> void:
	await _vault([&"door"])
	main.player.take_hit(main.player.stats.max_health / 2)
	await wait_physics_frames(5)
	assert_eq(main.player.stats.health * 2, main.player.stats.max_health)
	assert_eq(main.hud.notice(), "", "half is not under half")
	main.player.take_hit(1)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"door"])


# --- Once only ---

func test_a_hint_seen_does_not_come_back_after_a_fall_or_a_reload_but_does_in_a_new_game() -> void:
	await _vault([&"pause"])
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"pause"])
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	main.reload_checkpoint()
	await wait_physics_frames(10)
	assert_ne(main.hud.notice(), Hints.TEXTS[&"pause"], "not after a fall")
	assert_true(main.state.has_flag(Hints.flag(&"pause")))
	# The page reloaded: a new game scene on the same save.
	var path: String = main.store.path
	main.queue_free()
	await wait_physics_frames(2)
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = path
	main.show_title = false
	main.opening_enabled = false
	main.state = main.store.load_state()
	add_child_autofree(main)
	await wait_physics_frames(10)
	assert_eq(main.room.room_id, &"vault")
	assert_ne(main.hud.notice(), Hints.TEXTS[&"pause"], "not after a reload")
	main.new_game()
	await wait_physics_frames(3)
	assert_false(main.state.has_flag(Hints.flag(&"pause")), "a new game starts them afresh")


func test_the_skirmish_shows_a_hint_once_per_page_load() -> void:
	main = add_child_autofree(SKIRMISH.instantiate())
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"pause"])
	main.start_room()
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "")
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	main.reload_checkpoint()
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "")


# --- Never over a conversation, a card or the fall prompt ---

func test_a_hint_waits_for_a_conversation_to_end() -> void:
	await _vault([&"dry"])
	main.talk(HAVEN, "smith")
	await wait_physics_frames(2)
	assert_true(main.is_talking())
	_set_blood(main.player, 20)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "")
	main.dialogue.stop()
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])


func test_a_hint_waits_for_the_controls_card_and_one_on_show_goes_when_it_opens() -> void:
	await _vault([&"dry", &"door"])
	await _open_controls()
	_set_blood(main.player, 20)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "", "not over the card")
	await _open_controls()
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])
	await _open_controls()
	assert_eq(main.hud.notice(), "", "put away under the card")


func test_no_hint_shows_over_the_fall_prompt() -> void:
	await _vault([&"dry"])
	_set_blood(main.party[1], 20)
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(10)
	assert_true(main.hud.is_fallen_shown())
	assert_eq(main.hud.notice(), "")
	assert_false(main.state.has_flag(Hints.flag(&"dry")))


func test_a_hint_whose_moment_passes_while_it_waits_is_dropped() -> void:
	await _vault([&"dry"])
	await _open_controls()
	_set_blood(main.player, 20)
	await wait_physics_frames(5)
	_set_blood(main.player, 60)
	await _open_controls()
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "")
	assert_false(main.state.has_flag(Hints.flag(&"dry")), "it can still come when it applies again")
	_set_blood(main.player, 20)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])


# --- Beside the game's own notices ---

func test_a_hint_waits_while_another_notice_is_up() -> void:
	await _vault([&"dry"])
	main.hud.show_notice(Main.TIRING_NOTICE)
	_set_blood(main.player, 20)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), Main.TIRING_NOTICE)
	await wait_until(func() -> bool: return main.hud.notice() == Hints.TEXTS[&"dry"], main.hud.notice_time + 1.0)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])


func test_a_game_notice_replaces_a_hint_and_the_hint_does_not_come_back() -> void:
	await _vault([&"dry"])
	_set_blood(main.player, 20)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])
	main.hud.show_notice(Travel.FIGHT_TEXT)
	assert_eq(main.hud.notice(), Travel.FIGHT_TEXT)
	await wait_until(func() -> bool: return main.hud.notice() == "", main.hud.notice_time + 1.0)
	await wait_physics_frames(10)
	assert_eq(main.hud.notice(), "")


func test_a_hint_stays_six_seconds_and_the_next_waits_its_turn_by_urgency() -> void:
	await _vault([&"dry", &"door"])
	_set_blood(main.player, 20)
	main.player.take_hit(main.player.stats.health - main.player.stats.max_health / 3 + 5)
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"door"], "the door outranks the others")
	await wait_seconds(Hints.SHOW_TIME - 1.5)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"door"], "longer on show than a door's line")
	await wait_until(func() -> bool: return main.hud.notice() == Hints.TEXTS[&"dry"], 3.0)
	assert_eq(main.hud.notice(), Hints.TEXTS[&"dry"])


# --- A whole fight ---

## Three fights by the scripted player and two by the spam clicker, who uses no Rite and feeds only by
## chance, so he is shown the hints the player has no need of.
func test_a_fight_played_through_shows_each_hint_at_most_once_and_one_at_a_time() -> void:
	var runs: Array = [[VaultFight.Kind.PLAYER, 1000], [VaultFight.Kind.PLAYER, 1001],
			[VaultFight.Kind.PLAYER, 1002], [VaultFight.Kind.SPAM, 1000], [VaultFight.Kind.SPAM, 1001]]
	for run: Array in runs:
		var kind: VaultFight.Kind = run[0]
		var seed_value: int = run[1]
		if is_instance_valid(main):
			Story.finish(main)
			main.queue_free()
			await wait_physics_frames(2)
		seed(seed_value)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		main = Story.boot(self, VaultFight.state_for(VaultFight.Start.SPARED))
		var seen: Array[StringName] = []
		var at: Array[int] = []
		var named: Array[String] = []
		_hints().shown.connect(func(id: StringName) -> void:
			seen.append(id)
			at.append(Engine.get_physics_frames())
			if Hints.TEXTS[id].contains("%s"):
				named.append(_shown_text()))
		await wait_physics_frames(3)
		await VaultFight.settle(self, main)
		VaultFight.jitter(main, rng)
		VaultFight.speed_up()
		var fight := VaultFight.new(main, kind)
		var result: Dictionary = await fight.play(self, 180.0)
		VaultFight.slow_down()
		gut.p("%s seed %d: %s in %.1f s, hints %s at %s; %s" % [VaultFight.Kind.keys()[kind], seed_value,
				result.outcome, result.time, seen, at.map(func(frame: int) -> String:
					return "%.1f s" % ((frame - at[0]) / float(VaultFight.BASE_TICKS))), named])
		assert_has(seen, &"pause", "the first hint")
		assert_lte(seen.size(), Hints.ORDER.size())
		for id: StringName in Hints.ORDER:
			assert_lte(seen.count(id), 1, "%s once at most" % id)
		if seen.has(&"dry"):
			assert_has(seen, &"feed", "running dry only once feeding is taught: %s" % [seen])
			assert_lt(seen.find(&"feed"), seen.find(&"dry"), "feeding before running dry: %s" % [seen])
		for i: int in range(1, at.size()):
			assert_gte(at[i] - at[i - 1], roundi(Hints.GAP * VaultFight.BASE_TICKS) - 1,
					"no two hints within %s s: %s" % [Hints.GAP, seen])


# --- In Spanish ---

func test_every_hint_has_spanish() -> void:
	Language.apply("es")
	for id: StringName in Hints.ORDER:
		assert_ne(tr(Hints.TEXTS[id]), Hints.TEXTS[id], String(id))
	assert_eq(tr(Hints.TEXTS[&"dry"]) % "Zahra", "Zahra se queda sin Sangre. Aliméntate, o la Furia elegirá por ti.")
	TranslationServer.set_locale("en")
