class_name VaultFight
extends RefCounted
## Test helper: plays the story's vault with brains on, as one of three scripted players, through the
## calls a player's clicks and keys make (`PlayerInput.press_gift`, and the orders and Gift use that
## `PlayerInput.click_at` gives), and reports how the fight went. Each run is varied: every unit's start
## is moved within `JITTER` of its marker by a generator seeded for the run, and the fight runs on game
## time, faster than the clock, bounded by `limit` seconds of it.
##
## - CLICKER: Álvar attacks the nearest living enemy, and again when it dies. No Rites, no feeding.
## - PLAYER: as the clicker, and: Iron Sinew when it is off and he can pay; Baleful Eye on a sergeant
##   when he can pay; a feed on the nearest marked enemy whenever his Blood is under half; a companion
##   whose Blood is under a third is told to feed on the nearest enemy it can feed on. "Can pay" keeps
##   him at or above the Fury's line: a careful player does not spend himself into it.
## - COWARD: as the clicker until Álvar's health is under a third, then he walks to the west door and
##   uses it, again whenever the walk ends without it.
##
## A companion's feed is ordered as the player's order (`Unit.Issuer.PLAYER`), as selecting them,
## clicking the meal and selecting Álvar again would leave it; the selection itself is not changed.

enum Kind { CLICKER, PLAYER, COWARD }

## How the vault is entered: the captive spared (the least Blood a new game brings), drained (the
## most), or every member at no Blood at all.
enum Start { SPARED, DRAINED, DRY }

## Every unit starts at most this far from its marker, flat.
const JITTER: float = 1.0
## The script decides this often, in seconds of game time.
const STEP: float = 0.1
## How many times faster than the clock the fight runs.
const SPEED: float = 12.0
const BASE_TICKS: int = 60

var main: Main
var kind: Kind
## Party feeds completed, Álvar's Rites used, companions' Rites used, Furies begun (anyone in the party).
var feeds: int = 0
var rites: int = 0
var companion_rites: int = 0
var furies: int = 0
## Whether the coward has turned for the door.
var turned: bool = false


func _init(on: Main, as_kind: Kind) -> void:
	main = on
	kind = as_kind
	for member: Unit in main.party:
		member.fed.connect(func(_target: Unit) -> void: feeds += 1)
		member.fury_started.connect(func() -> void: furies += 1)
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
## of game time pass. Returns the outcome: "cleared", "fall", "left" or "timeout", with the game time
## taken. The caller has booted `main` and jittered it.
func play(test: GutTest, limit: float) -> Dictionary:
	var ticks: int = roundi(STEP * BASE_TICKS)
	var steps: int = roundi(limit / STEP)
	var outcome: String = "timeout"
	var elapsed: float = 0.0
	for step: int in steps:
		decide()
		await test.wait_physics_frames(ticks)
		elapsed += STEP
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
		"outcome": outcome, "time": elapsed, "turned": turned,
		"health": alvar.stats.health if is_instance_valid(alvar) else -1,
		"blood": alvar.stats.blood if is_instance_valid(alvar) else -1,
		"feeds": feeds, "rites": rites, "companion_rites": companion_rites, "furies": furies,
	}


## One decision of the scripted player.
func decide() -> void:
	var alvar: Unit = main.player
	if alvar == null or not alvar.is_alive() or alvar.is_in_fury():
		return
	if kind == Kind.COWARD and _retreat(alvar):
		return
	if kind == Kind.PLAYER:
		_tell_companions_to_feed()
		if alvar.feed_target() != null:
			return
		if alvar.stats.blood * 2 < alvar.stats.max_blood and _feed(alvar):
			return
		_rites(alvar)
	_attack_nearest(alvar)


func _attack_nearest(alvar: Unit) -> void:
	var current: Unit = alvar.attack_target()
	# The player leaves a companion's meal alone; the clicker does not look.
	if current != null and current.is_alive() and not (kind == Kind.PLAYER and _claimed(current, alvar)):
		return
	var enemy: Unit = nearest_enemy(alvar.global_position, kind == Kind.PLAYER)
	if enemy != null:
		alvar.order_attack(enemy)


## Feeds on the nearest marked enemy; whether he took the order.
func _feed(alvar: Unit) -> bool:
	var best: Unit = null
	var best_distance: float = INF
	for enemy: Unit in main.enemies:
		if enemy.has_feed_mark() and alvar.can_feed_on(enemy) and not _claimed(enemy, alvar):
			var distance: float = _flat(enemy.global_position, alvar.global_position)
			if distance < best_distance:
				best_distance = distance
				best = enemy
	if best == null:
		return false
	alvar.order_feed(best)
	return alvar.feed_target() == best


func _rites(alvar: Unit) -> void:
	var gifts: GiftUser = alvar.get_node(^"Gifts")
	var keep: int = alvar.fury_threshold
	for index: int in gifts.count():
		var gift: Gift = gifts.gift(index)
		if not gifts.is_ready(index) or alvar.stats.blood - gift.blood_cost < keep:
			continue
		if gift.id == &"iron_sinew" and not alvar.has_effect(&"iron_sinew") and _fight_near(alvar):
			main.input.press_gift(index)
		elif gift.id == &"baleful_eye":
			var sergeant: Unit = _sergeant_in_reach(alvar, gift)
			if sergeant != null:
				# What a press of the Rite's key and a click on the sergeant do.
				main.input.press_gift(index)
				gifts.use(index, sergeant)
				main.input.cancel_targeting()


## Whether an enemy is near enough that a Rite to fight with is worth calling.
func _fight_near(alvar: Unit) -> bool:
	var enemy: Unit = nearest_enemy(alvar.global_position, false)
	return enemy != null and _flat(enemy.global_position, alvar.global_position) <= 4.0


func _sergeant_in_reach(alvar: Unit, gift: Gift) -> Unit:
	var best: Unit = null
	var best_distance: float = INF
	for enemy: Unit in main.enemies:
		if enemy.display_name != "Sergeant" or not gift.can_target(alvar, enemy):
			continue
		if enemy.is_stunned():
			continue
		var distance: float = _flat(enemy.global_position, alvar.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _tell_companions_to_feed() -> void:
	for member: Unit in main.party:
		if member == main.player or not member.is_alive() or member.is_in_fury():
			continue
		if member.feed_target() != null or member.stats.blood * 3 >= member.stats.max_blood:
			continue
		var best: Unit = null
		var best_distance: float = INF
		for enemy: Unit in main.enemies:
			if member.can_feed_on(enemy) and not _claimed(enemy, member):
				var distance: float = _flat(enemy.global_position, member.global_position)
				if distance < best_distance:
					best_distance = distance
					best = enemy
		if best != null:
			member.order_feed(best)


## Whether someone other than `who` has a feed order on `enemy`.
func _claimed(enemy: Unit, who: Unit) -> bool:
	for member: Unit in main.party:
		if member != who and member.feed_target() == enemy:
			return true
	return false


## The coward's turn: under a third of his health he heads for the west door. Returns whether he has turned.
func _retreat(alvar: Unit) -> bool:
	if not turned and alvar.stats.health * 3 < alvar.stats.max_health:
		turned = true
	if not turned:
		return false
	if alvar.current_order() != Unit.Order.INTERACT:
		alvar.order_interact(main.room.find_child("WestDoor") as Door)
	return true


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
