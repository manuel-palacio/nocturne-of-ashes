class_name VaultFight
extends RefCounted
## Test helper: plays the story's vault with brains on, as a person clicks: once a second (the spam
## clicker every 1.2 s), only through `PlayerInput.click_at`, `press_gift` and `press_member`, the calls
## a click, a key and a press on a party panel make. A click is aimed as a person aims: at a part of the
## target that no one else covers, so a click on a marked enemy feeds whenever the game's rule says a
## click feeds. Each run is varied (every unit moved within `JITTER` of its marker by a seeded
## generator) and runs on game time, faster than the clock, bounded by `limit` seconds of it.
##
## - SPAM: clicks the nearest living enemy every 1.2 s. No Rites, no pause, no orders to companions.
## - PLAYER: once a second, the first of: feed on a marked enemy within `REACH` when his Blood or his
##   health is under half; have a companion under a third of health or Blood feed (press their panel,
##   click the meal, press Álvar's panel); Baleful Eye on a sergeant attacking a party member, when he
##   can pay; Iron Sinew when it is off and he can pay; a click on the nearest enemy when he has no
##   target. "Can pay" keeps him at or above the Fury's line.
## - NO_RITES: the player without Iron Sinew and Baleful Eye.
## - NO_FEED: the player who never feeds and never has a companion feed; he never clicks a marked enemy
##   while a click would feed (his Blood short of full), and waits when only such enemies are left.
## - COWARD: the spam clicker until Álvar's health is under a third, then once a second a click on the
##   west door.

enum Kind { SPAM, PLAYER, NO_RITES, NO_FEED, COWARD }

## How the vault is entered: the captive spared (the least Blood a new game brings), drained (the
## most), or every member at no Blood at all.
enum Start { SPARED, DRAINED, DRY }

## Every unit starts at most this far from its marker, flat.
const JITTER: float = 1.0
## The script looks at the fight this often, in seconds of game time.
const STEP: float = 0.1
## A person acts once a second; the spam clicker every 1.2 s.
const ACT_EVERY: float = 1.0
const SPAM_EVERY: float = 1.2
## A marked enemy this near Álvar, flat, is one the player goes to drink from.
const REACH: float = 6.0
## How many times faster than the clock the fight runs.
const SPEED: float = 12.0
const BASE_TICKS: int = 60
## Heights on a unit a click is aimed at, head first.
const AIM: Array[float] = [1.5, 1.1, 0.6]

var main: Main
var kind: Kind
## Party feeds completed, Álvar's Rites used, companions' Rites used, Furies begun (anyone in the party),
## and companions who fell at least once.
var feeds: int = 0
var rites: int = 0
var companion_rites: int = 0
var furies: int = 0
var fallen_companions: Dictionary = {}  # StringName -> true
## Whether the coward has turned for the door.
var turned: bool = false

var _clock: float = 0.0
var _next_act: float = 0.0


func _init(on: Main, as_kind: Kind) -> void:
	main = on
	kind = as_kind
	for member: Unit in main.party:
		member.fed.connect(func(_target: Unit) -> void: feeds += 1)
		member.fury_started.connect(func() -> void: furies += 1)
		member.died.connect(func(unit: Unit) -> void:
			if unit != main.player:
				fallen_companions[unit.member_id] = true)
		var gifts: GiftUser = member.get_node(^"Gifts")
		if member == main.player:
			gifts.gift_used.connect(func(_index: int, _target: Unit) -> void: rites += 1)
		else:
			gifts.gift_used.connect(func(_index: int, _target: Unit) -> void: companion_rites += 1)


## The story state for `start`, at the vault's door from the haven.
static func state_for(start: Start) -> GameState:
	var state := PageBoot.haven_finished()
	match start:
		Start.SPARED:
			state.set_flag(&"captive_spared")
		Start.DRAINED:
			state.set_flag(&"captive_dead")
			state.set_vitals(GameState.LEADER, -1, 100)
		Start.DRY:
			for member: StringName in GameState.MEMBERS:
				state.set_vitals(member, -1, 0)
	return state


## Moves every unit in the room within `JITTER` of where it stands, by `rng`.
static func jitter(on: Main, rng: RandomNumberGenerator) -> void:
	for unit: Unit in on.party + on.enemies:
		var angle: float = rng.randf() * TAU
		var radius: float = sqrt(rng.randf()) * JITTER
		unit.global_position += Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Waits until the room's navigation map has synced, which happens once a drawn frame, not once a
## physics tick: a fight begun before it would wait for its first paths a number of ticks that depends
## on the machine's load, and the same seed would give another fight.
## The world is held (the pause) meanwhile, so the units' brains and walks do not run on through a
## number of ticks that depends on the load either.
static func settle(test: GutTest, on: Main) -> void:
	on.set_paused(true)
	var map: RID = on.get_world_3d().navigation_map
	await test.wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > 0, 5.0)
	await test.wait_process_frames(2)
	on.set_paused(false)


## Runs the engine `SPEED` times faster than the clock, each physics tick still 1/60 s of game time.
static func speed_up() -> void:
	Engine.time_scale = SPEED
	Engine.physics_ticks_per_second = roundi(BASE_TICKS * SPEED)
	Engine.max_physics_steps_per_frame = 64


static func slow_down() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = BASE_TICKS
	Engine.max_physics_steps_per_frame = 8


## Plays until the vault is cleared, Álvar falls, the party leaves through a door, or `limit` seconds
## of game time pass. Returns the outcome ("cleared", "fall", "left" or "timeout") and what it took.
## The caller has booted `main` and jittered it.
func play(test: GutTest, limit: float) -> Dictionary:
	var ticks: int = roundi(STEP * BASE_TICKS)
	var steps: int = roundi(limit / STEP)
	var outcome: String = "timeout"
	for step: int in steps:
		decide()
		await test.wait_physics_frames(ticks)
		_clock += STEP
		if main.room.room_id != &"vault":
			outcome = "left"
			break
		if main.is_cleared():
			outcome = "cleared"
			break
		if not main.player.is_alive():
			outcome = "fall"
			break
	var alvar: Unit = main.player
	return {
		"outcome": outcome, "time": _clock, "turned": turned,
		"health": alvar.stats.health if is_instance_valid(alvar) else -1,
		"blood": alvar.stats.blood if is_instance_valid(alvar) else -1,
		"feeds": feeds, "rites": rites, "companion_rites": companion_rites, "furies": furies,
		"companions_fallen": fallen_companions.size(),
	}


## Called every `STEP` of game time: acts when the person's next moment has come.
func decide() -> void:
	var alvar: Unit = main.player
	if alvar == null or not alvar.is_alive() or _clock < _next_act:
		return
	_next_act = _clock + (SPAM_EVERY if kind == Kind.SPAM else ACT_EVERY)
	if kind == Kind.COWARD:
		if not turned and alvar.stats.health * 3 < alvar.stats.max_health:
			turned = true
		if turned:
			_click_door()
			return
	if kind == Kind.SPAM or kind == Kind.COWARD:
		_click_unit(nearest_enemy(alvar.global_position, false))
		return
	if alvar.is_in_fury() or alvar.feed_target() != null:
		return
	if kind != Kind.NO_FEED:
		var short: bool = alvar.stats.blood * 2 < alvar.stats.max_blood or alvar.stats.health * 2 < alvar.stats.max_health
		if short and _feed(alvar):
			return
		if _companion_feeds():
			return
	if kind != Kind.NO_RITES and _rites(alvar):
		return
	var current: Unit = alvar.attack_target()
	if current != null and current.is_alive() and not _claimed(current, alvar):
		return
	_click_unit(_target_for(alvar))


## The enemy the player clicks to fight: the nearest living one, not held by a feed; the one who never
## feeds passes over the marked while a click on them would feed.
func _target_for(alvar: Unit) -> Unit:
	var best: Unit = null
	var best_distance: float = INF
	var avoid_marked: bool = kind == Kind.NO_FEED and alvar.stats.blood < alvar.stats.max_blood
	for enemy: Unit in main.enemies:
		if not enemy.is_alive() or Feeder.is_held(enemy) or _claimed(enemy, alvar):
			continue
		if avoid_marked and alvar.can_feed_on(enemy):
			continue
		var distance: float = _flat(enemy.global_position, alvar.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## A click on the nearest marked enemy within `REACH`; whether one was clicked.
func _feed(alvar: Unit) -> bool:
	var best: Unit = null
	var best_distance: float = REACH
	for enemy: Unit in main.enemies:
		if enemy.has_feed_mark() and alvar.can_feed_on(enemy) and not _claimed(enemy, alvar):
			var distance: float = _flat(enemy.global_position, alvar.global_position)
			if distance <= best_distance:
				best_distance = distance
				best = enemy
	return best != null and _click_unit(best)


## A companion under a third of health or Blood is pressed, a meal it can feed on clicked, and Álvar
## pressed again. Whether a companion was told to feed.
func _companion_feeds() -> bool:
	for member: Unit in main.party:
		if member == main.player or not member.is_alive() or member.is_in_fury() or member.feed_target() != null:
			continue
		var low: bool = member.stats.health * 3 < member.stats.max_health or member.stats.blood * 3 < member.stats.max_blood
		if not low:
			continue
		var best: Unit = null
		var best_distance: float = REACH
		for enemy: Unit in main.enemies:
			if member.can_feed_on(enemy) and not _claimed(enemy, member):
				var distance: float = _flat(enemy.global_position, member.global_position)
				if distance <= best_distance:
					best_distance = distance
					best = enemy
		if best == null:
			continue
		main.input.press_member(member)
		var told: bool = _click_unit(best) and member.feed_target() == best
		main.input.press_member(main.player)
		if told:
			return true
	return false


## Iron Sinew when it is off; Baleful Eye on a sergeant attacking a party member. Whether one was used.
func _rites(alvar: Unit) -> bool:
	var gifts: GiftUser = alvar.get_node(^"Gifts")
	for index: int in gifts.count():
		var gift: Gift = gifts.gift(index)
		if not gifts.is_ready(index) or alvar.stats.blood - gift.blood_cost < alvar.fury_threshold:
			continue
		if gift.id == &"baleful_eye":
			var sergeant: Unit = _sergeant_to_stare_down(alvar, gift)
			if sergeant == null:
				continue
			main.input.press_gift(index)
			_click_unit(sergeant)
			if main.input.targeting_gift() >= 0:
				main.input.cancel_targeting()
				continue
			return true
		if gift.id == &"iron_sinew" and not alvar.has_effect(&"iron_sinew") and _fight_near(alvar):
			main.input.press_gift(index)
			return true
	return false


## Whether an enemy is near enough that a Rite to fight with is worth calling.
func _fight_near(alvar: Unit) -> bool:
	var enemy: Unit = nearest_enemy(alvar.global_position, false)
	return enemy != null and _flat(enemy.global_position, alvar.global_position) <= 4.0


## The nearest sergeant in the Eye's reach who is attacking a party member and is not stunned.
func _sergeant_to_stare_down(alvar: Unit, gift: Gift) -> Unit:
	var best: Unit = null
	var best_distance: float = INF
	for enemy: Unit in main.enemies:
		if enemy.display_name != "Sergeant" or enemy.is_stunned() or not gift.can_target(alvar, enemy):
			continue
		var victim: Unit = enemy.attack_target()
		if victim == null or not main.party.has(victim):
			continue
		var distance: float = _flat(enemy.global_position, alvar.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## Clicks `target` where the click reaches it: its head, chest or legs, whichever no one else covers.
## Whether it was clicked.
func _click_unit(target: Unit) -> bool:
	if target == null or not target.is_alive():
		return false
	var camera: Camera3D = _settled_camera()
	for up: float in AIM:
		var point: Vector3 = target.global_position + Vector3.UP * up
		if camera.is_position_behind(point):
			continue
		var at: Vector2 = camera.unproject_position(point)
		if Picker.unit_at(camera, at) == target:
			main.input.click_at(at)
			return true
	return false


func _click_door() -> void:
	var door := main.room.find_child("WestDoor") as Door
	var camera: Camera3D = _settled_camera()
	for up: float in [1.0, 1.6, 0.4]:
		var at: Vector2 = camera.unproject_position(door.global_position + Vector3.UP * up)
		if Picker.interactable_at(camera, at) == door:
			main.input.click_at(at)
			return
	# Not in view: a click on the floor towards it, as a person walks towards a door off screen.
	main.input.click_at(camera.unproject_position(door.global_position))


## The camera, settled on whom it follows. The rig follows in drawn frames, whose count per physics tick
## depends on the machine's load; settled first, a click lands where it would on any machine, and the
## same seed plays the same fight.
func _settled_camera() -> Camera3D:
	main.rig.snap_to_target()
	return main.rig.camera()


## Whether someone other than `who` has a feed order on `enemy`.
func _claimed(enemy: Unit, who: Unit) -> bool:
	for member: Unit in main.party:
		if member != who and member.feed_target() == enemy:
			return true
	return false


## The nearest living enemy to `from`; with `open_only`, not one held by a feed.
func nearest_enemy(from: Vector3, open_only: bool) -> Unit:
	var best: Unit = null
	var best_distance: float = INF
	for enemy: Unit in main.enemies:
		if not enemy.is_alive() or (open_only and Feeder.is_held(enemy)):
			continue
		var distance: float = _flat(enemy.global_position, from)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
