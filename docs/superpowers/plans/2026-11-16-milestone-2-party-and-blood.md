# Milestone 2: Party and Blood Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three characters fight six crusaders in the vault room, in the browser: select and order each of them, pause to give orders, spend Blood on six Gifts, feed on weakened enemies, and lose control to the Fury when Blood runs out.

**Architecture:** `Unit` keeps orders and state; navigation moves into a `Mover` child, timed modifiers into `StatusEffect` resources, powers into `Gift` resources run by a `GiftUser` child. One `CombatBrain` drives enemies and unselected companions. `Main` owns the party, the selection and the pause; `PlayerInput` turns clicks and keys into orders through a shared `Picker`; `Hud` shows the party, the selected character's Gifts and the state of the room.

**Tech Stack:** Godot 4.7.2, GDScript, GUT 9.6.1, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md`

**Builds on:** `docs/superpowers/plans/2026-11-15-milestone-1-first-room.md`, including its "Amendments" and "Carried forward" sections.

## Global Constraints

- Godot **4.7**, GDScript only, rendering method `gl_compatibility`. Web export with threads and extensions off.
- No name, term, text, sound or image from *Vampire: The Masquerade – Redemption* or the World of Darkness. Use the spec's vocabulary: the Turning, Gifts, Conscience, the Long Sleep, the Veil, the Fury.
- Third-party assets and add-ons are CC0, CC-BY or MIT, each listed in `CREDITS.md`.
- Commits: Conventional Commits, subject 72 characters or fewer, one logical change each, authored as `Manuel <emanuel.palacio@gmail.com>`, ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Typed GDScript throughout, tabs, one class per file with `class_name` (the `Probe` autoload is the one exception).
- Metres and seconds. Ground plane is XZ, Y up. Distances between units are measured flat on XZ.
- All gameplay numbers are `@export` variables with the defaults given here.
- Physics layers: 1 "world" (floor, pillars), 2 "units", 3 "walls". Unit bodies sit on layer 2 and collide with 1 and 3.
- Test code given in a task is used verbatim. Tests from earlier work stay unchanged unless the task names the change. A test that cannot pass as written is reported, not edited.
- Test output is clean: the only warning allowed is the one the existing stall test expects.
- Pausing never uses `SceneTree.paused`; it disables processing of the units container (Task 5). GUT's own waits must keep running.
- Placeholder look only: capsules, boxes, plain panels. No new art, sound or particles.
- Every task ends with `ops/test.sh` passing in full. Each task states how many tests its new files add; the running total is whatever the suite reports.

## Review Focus

1. **An order given while the unit cannot act** (stunned, feeding, in the Fury, or with the world paused): stunned and paused units keep the order and carry it out afterwards; a feeding unit breaks off its feed and obeys; a unit in the Fury ignores it. Never an error, never a unit left idle with an order. Tests in Tasks 2, 5 and 6.
2. **A target that dies or is freed between choosing a Gift and clicking, or mid-feed:** the Gift is not spent and targeting stays open; the feed ends with no Blood gained and the feeder free to act. Tests in Tasks 6 and 9.
3. **The selected companion falls:** selection moves to Álvar, Gift targeting is cancelled, the camera follows Álvar. Test in Task 4 and Task 9.
4. **Restart from any state** (paused, mid-Fury, mid-targeting, companions down): the new round starts unpaused, with three living party members at full health, Blood at its starting value, no effects, no cooldowns, Álvar selected. Test in Task 5 and Task 9.
5. **Spending Blood at the edges:** a Gift that costs more Blood than the unit has is refused and costs nothing; a Gift that takes Blood below the Fury threshold works and then starts the Fury; Blood never goes negative or above its maximum. Tests in Tasks 6 and 7.

## File Structure

```
src/units/mover.gd             Mover: paths, navmesh readiness, height gap, stall check
src/units/status_effect.gd     StatusEffect: one timed modifier
src/units/unit.gd              Unit: orders, state, effects, hits, feeding, the Fury, death and revival
src/units/stats.gd             (modify) starting blood, revive, guards
src/units/melee_attack.gd      (modify) hits through Unit, respects effects
src/units/combat_brain.gd      CombatBrain: replaces enemy_brain.gd
src/gifts/gift.gd              Gift: base resource
src/gifts/gift_user.gd         GiftUser: a unit's Gifts, costs and cooldowns
src/gifts/iron_sinew.gd  baleful_eye.gd  mend_flesh.gd  blood_lance.gd  stone_hide.gd  hammerfall.gd
resources/gifts/*.tres         one resource per Gift
src/player/picker.gd           Picker: unit or ground under a screen point
src/player/player_input.gd     (modify) selection, Gift keys, targeting
src/main.gd                    (modify) party, selection, pause, fight flow
src/ui/hud.gd                  (rewrite) party panel, Gift bar, state labels
src/ui/party_member_panel.gd   PartyMemberPanel: one portrait with bars
src/ui/gift_button.gd          GiftButton: one Gift with cost and cooldown
src/core/probe.gd              (modify) party state for browser tests
scenes/units/unit_base.tscn    shared unit layout; alvar, zahra, gonzalo, crusader inherit it
scenes/ui/hud.tscn  party_member_panel.tscn  gift_button.tscn
tests/support/arena.gd         Arena: shared test fixture helper
tests/…                        one file per task, named in each task
e2e/smoke.spec.js  e2e/party.spec.js
```

---

### Task 1: Mover, order state and a base unit scene

A refactor: no behaviour changes. The existing suite is the safety net.

**Files:**
- Create: `src/units/mover.gd`, `scenes/units/unit_base.tscn`, `tests/support/arena.gd`, `tests/units/test_unit_orders.gd`
- Modify: `src/units/unit.gd`, `scenes/units/alvar.tscn`, `scenes/units/crusader.tscn`

**Interfaces:**
- Produces: `class_name Mover extends Node` (child of a `Unit`, node name `Mover`)
  - `signal arrived`, `signal stalled`
  - `var stall_check: bool = true`
  - `func walk_to(target: Vector3) -> void`, `func halt() -> void`, `func is_walking() -> bool` (true from the moment `walk_to` is called until arrival, halt or stall), `func destination() -> Vector3`
  - Owns everything `unit.gd` now does with `NavigationAgent3D` and `NavigationServer3D`: holding a walk until the map has a navmesh and the unit stands on the floor, the height gap, re-measuring on landing, and the stall check (emit `stalled` after `push_warning`, with the same message as now). The `Agent` node becomes the Mover's concern.
  - `Unit` still owns gravity, `move_and_slide()` and facing. How `Unit` asks `Mover` for its horizontal velocity each physics frame is the implementer's choice. After this task `unit.gd` contains no reference to `NavigationServer3D` or `NavigationAgent3D`.
- Produces, on `Unit`:
  - `enum Order { NONE, MOVE, ATTACK }` and `func current_order() -> Order`, replacing the `_moving` / `_attack_target` flag pair as the source of truth.
  - All existing public methods and signals keep their names and behaviour: `order_move`, `order_attack`, `attack_target`, `stop`, `is_moving`, `is_alive`, `is_hostile_to`, `died`, `arrived` (move orders only), `attack_ended`.
- Produces: `scenes/units/unit_base.tscn` — root `Unit` (`CharacterBody3D`, layer 2, mask 5) with `CollisionShape3D`, `Body`, `Agent`, `Mover`, `Melee`. `alvar.tscn` and `crusader.tscn` become inherited scenes that override only what differs (stats, faction, speed, name, body material, melee numbers; the crusader adds `Brain`).
- Produces: `class_name Arena extends RefCounted` in `tests/support/arena.gd`

```gdscript
class_name Arena
extends RefCounted
## Test helper: the flat fixture room with units placed in it.

const ROOM: PackedScene = preload("res://tests/fixtures/flat_room.tscn")
const ALVAR: PackedScene = preload("res://scenes/units/alvar.tscn")
const CRUSADER: PackedScene = preload("res://scenes/units/crusader.tscn")

var room: Node3D


func _init(test: GutTest) -> void:
	room = test.add_child_autofree(ROOM.instantiate())


## Adds a unit at `at`. Its Brain, if it has one, is removed unless `with_brain` is true.
func spawn(scene: PackedScene, at: Vector3, with_brain: bool = false) -> Unit:
	var unit: Unit = scene.instantiate()
	var brain: Node = unit.get_node_or_null(^"Brain")
	if brain != null and not with_brain:
		unit.remove_child(brain)
		brain.free()
	room.add_child(unit)
	unit.global_position = at
	return unit


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
```

- [ ] **Step 1: Run the suite and note the count** — `ops/test.sh`. Expected: all pass.

- [ ] **Step 2: Write the new tests** (5 tests)

```gdscript
# tests/units/test_unit_orders.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_physics_frames(3)

func test_a_new_unit_has_no_order() -> void:
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_move_order_shows_until_arrival() -> void:
	alvar.order_move(Vector3(3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)
	await wait_for_signal(alvar.arrived, 4.0)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_an_attack_order_shows_until_the_target_dies() -> void:
	alvar.order_attack(foe)
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	await wait_for_signal(foe.died, 12.0)
	await wait_physics_frames(3)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_stop_clears_the_order() -> void:
	alvar.order_attack(foe)
	alvar.stop()
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_null(alvar.attack_target())

func test_every_unit_scene_has_a_mover() -> void:
	assert_not_null(alvar.get_node_or_null(^"Mover") as Mover)
	assert_not_null(foe.get_node_or_null(^"Mover") as Mover)
```

- [ ] **Step 3: Run to verify failure** — `ops/test.sh -gtest=res://tests/units/test_unit_orders.gd`. Expected: script errors for `Arena`, `Unit.Order`, `Mover`.
- [ ] **Step 4: Create `Arena`, the base scene and `Mover`; move the navigation code out of `Unit`; introduce `Order`.**
- [ ] **Step 5: Run the full suite** — `ops/test.sh`. Expected: every earlier test passes unchanged, plus 5.
- [ ] **Step 6: Commit** — three commits: `test: add a shared arena helper for unit tests`, `refactor: move navigation out of Unit into a Mover node`, `refactor: share one base scene between unit types`.

---

### Task 2: Hits, effects and revival

**Files:**
- Create: `src/units/status_effect.gd`, `tests/units/test_effects.gd`, `tests/units/test_hits_and_revival.gd`
- Modify: `src/units/unit.gd`, `src/units/stats.gd`, `src/units/melee_attack.gd`

**Interfaces:**
- Produces: `class_name StatusEffect extends Resource`
  - `@export var id: StringName`, `@export var duration: float = 1.0`, `@export var speed_multiplier: float = 1.0`, `@export var damage_dealt_multiplier: float = 1.0`, `@export var damage_taken_multiplier: float = 1.0`, `@export var stuns: bool = false`, `@export var taunt_radius: float = 0.0`
- Produces, on `Unit`:
  - `signal was_hit(amount: int, source: Unit)`, `signal effects_changed`, `signal revived(unit: Unit)`
  - `func add_effect(effect: StatusEffect) -> void` (stores a copy; an effect with the same `id` is replaced, which restarts its time), `func remove_effect(id: StringName) -> void`, `func has_effect(id: StringName) -> bool`, `func clear_effects() -> void`. Effects count down in `_physics_process` and are cleared on death.
  - `func is_stunned() -> bool`, `func speed_multiplier() -> float`, `func damage_dealt_multiplier() -> float`, `func damage_taken_multiplier() -> float` (products over active effects), `func taunt_radius() -> float` (largest over active effects)
  - `func take_hit(amount: int, source: Unit = null) -> int` — ignores amounts of 0 or less and dead units (returns 0). Otherwise deals `maxi(roundi(amount * damage_taken_multiplier()), 1)` through `stats.take_damage`, emits `was_hit`, returns the damage dealt.
  - A stunned unit does not walk and does not strike. It keeps its order, accepts new orders, and carries the current one out when the stun ends. Walking speed is `move_speed * speed_multiplier()`.
  - `func revive(health_fraction: float = 0.3) -> void` — only for a dead unit: health becomes `maxi(roundi(max_health * health_fraction), 1)`, the body stands up, the collision layer returns to 2, effects are cleared, order is `NONE`, emits `revived(self)`.
  - Death presentation is reversible and the fallen body rests on the floor (its lowest point within 0.05 m of the unit's origin height), instead of pivoting about its centre.
- Produces, on `Stats`:
  - `@export var starting_blood: int = -1` (−1 means full); `reset()` sets `blood` to `max_blood` or to `clampi(starting_blood, 0, max_blood)`.
  - `func revive(amount: int) -> void` — only when dead: `health = clampi(amount, 1, max_health)`, emits `health_changed`. `died` can fire again after a revival.
  - A `max_health` or `max_blood` of 0 or less is treated as 1 by `reset()`.
- Changes `MeleeAttack.try_hit`: returns false when its own unit is dead or stunned; deals `target.take_hit(roundi(damage * _unit.damage_dealt_multiplier()), _unit)`; `hit` carries the damage actually dealt.

- [ ] **Step 1: Write the failing tests** (9 + 8 tests)

```gdscript
# tests/units/test_effects.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func _effect(id: StringName, duration: float) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	return effect

func test_an_effect_lasts_its_duration() -> void:
	watch_signals(alvar)
	alvar.add_effect(_effect(&"test", 0.5))
	assert_true(alvar.has_effect(&"test"))
	assert_signal_emitted(alvar, "effects_changed")
	await wait_seconds(0.7)
	assert_false(alvar.has_effect(&"test"))

func test_the_same_id_replaces_and_restarts() -> void:
	alvar.add_effect(_effect(&"test", 0.5))
	await wait_seconds(0.3)
	alvar.add_effect(_effect(&"test", 0.5))
	await wait_seconds(0.3)
	assert_true(alvar.has_effect(&"test"))

func test_multipliers_combine() -> void:
	var a := _effect(&"a", 5.0)
	a.damage_dealt_multiplier = 1.5
	var b := _effect(&"b", 5.0)
	b.damage_dealt_multiplier = 2.0
	b.damage_taken_multiplier = 0.4
	alvar.add_effect(a)
	alvar.add_effect(b)
	assert_almost_eq(alvar.damage_dealt_multiplier(), 3.0, 0.001)
	assert_almost_eq(alvar.damage_taken_multiplier(), 0.4, 0.001)
	assert_almost_eq(alvar.speed_multiplier(), 1.0, 0.001)

func test_damage_taken_is_scaled_and_never_below_one() -> void:
	var hide := _effect(&"hide", 5.0)
	hide.damage_taken_multiplier = 0.4
	alvar.add_effect(hide)
	assert_eq(alvar.take_hit(10), 4)
	assert_eq(alvar.take_hit(1), 1)
	assert_eq(alvar.stats.health, 115)

func test_damage_dealt_is_scaled() -> void:
	var sinew := _effect(&"sinew", 5.0)
	sinew.damage_dealt_multiplier = 1.5
	alvar.add_effect(sinew)
	alvar.get_node("Melee").try_hit(foe)
	assert_eq(foe.stats.health, 60 - 23)  # round(15 * 1.5) = 23

func test_a_stunned_unit_neither_walks_nor_strikes_and_then_resumes() -> void:
	var stun := _effect(&"stun", 0.6)
	stun.stuns = true
	alvar.add_effect(stun)
	assert_true(alvar.is_stunned())
	assert_false(alvar.get_node("Melee").try_hit(foe))
	alvar.order_move(Vector3(4, 0, 0))
	await wait_seconds(0.4)
	assert_lt(Arena.flat(alvar.global_position, Vector3.ZERO), 0.1)
	assert_eq(alvar.current_order(), Unit.Order.MOVE)
	await wait_for_signal(alvar.arrived, 4.0)
	assert_lt(Arena.flat(alvar.global_position, Vector3(4, 0, 0)), 0.5)

func test_speed_is_scaled() -> void:
	var haste := _effect(&"haste", 5.0)
	haste.speed_multiplier = 2.0
	alvar.add_effect(haste)
	alvar.order_move(Vector3(8, 0, 0))
	await wait_seconds(1.0)
	assert_gt(alvar.global_position.x, 6.0)  # 4 m/s doubled, less a little start-up

func test_the_largest_taunt_radius_counts() -> void:
	var a := _effect(&"a", 5.0)
	a.taunt_radius = 4.0
	var b := _effect(&"b", 5.0)
	b.taunt_radius = 8.0
	alvar.add_effect(a)
	alvar.add_effect(b)
	assert_eq(alvar.taunt_radius(), 8.0)

func test_death_clears_effects() -> void:
	alvar.add_effect(_effect(&"test", 5.0))
	alvar.take_hit(999)
	assert_false(alvar.has_effect(&"test"))
```

```gdscript
# tests/units/test_hits_and_revival.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func test_a_hit_reports_its_amount_and_source() -> void:
	watch_signals(foe)
	assert_eq(foe.take_hit(10, alvar), 10)
	assert_signal_emitted_with_parameters(foe, "was_hit", [10, alvar])

func test_zero_negative_and_posthumous_hits_do_nothing() -> void:
	assert_eq(foe.take_hit(0), 0)
	assert_eq(foe.take_hit(-5), 0)
	foe.take_hit(999)
	assert_eq(foe.take_hit(10), 0)

func test_melee_goes_through_take_hit() -> void:
	watch_signals(foe)
	alvar.get_node("Melee").try_hit(foe)
	assert_signal_emitted_with_parameters(foe, "was_hit", [15, alvar])

func test_a_dead_unit_cannot_strike() -> void:
	alvar.take_hit(999)
	assert_false(alvar.get_node("Melee").try_hit(foe))

func test_a_fallen_body_rests_on_the_floor() -> void:
	alvar.take_hit(999)
	await wait_physics_frames(5)
	var body: MeshInstance3D = alvar.get_node("Body")
	var lowest: float = (body.global_transform * body.get_aabb()).position.y
	assert_almost_eq(lowest, alvar.global_position.y, 0.05)

func test_revival_restores_a_working_unit() -> void:
	watch_signals(alvar)
	alvar.take_hit(999)
	await wait_physics_frames(3)
	alvar.revive()
	await wait_physics_frames(3)
	assert_true(alvar.is_alive())
	assert_eq(alvar.stats.health, 36)  # 30% of 120
	assert_eq(alvar.collision_layer, 2)
	assert_signal_emitted(alvar, "revived")
	alvar.order_move(Vector3(3, 0, 0))
	await wait_for_signal(alvar.arrived, 4.0)
	assert_lt(Arena.flat(alvar.global_position, Vector3(3, 0, 0)), 0.5)

func test_a_revived_unit_can_die_again() -> void:
	watch_signals(alvar)
	alvar.take_hit(999)
	alvar.revive()
	alvar.take_hit(999)
	assert_signal_emit_count(alvar, "died", 2)

func test_reviving_the_living_does_nothing() -> void:
	alvar.take_hit(20)
	alvar.revive()
	assert_eq(alvar.stats.health, 100)
```

Also add to `tests/units/test_stats.gd` (3 tests, appended; the existing tests stay):

```gdscript
func test_starting_blood_is_used_when_set() -> void:
	stats.starting_blood = 60
	stats.reset()
	assert_eq(stats.blood, 60)

func test_revive_only_raises_the_dead() -> void:
	stats.revive(50)
	assert_eq(stats.health, 100)
	stats.take_damage(999)
	stats.revive(50)
	assert_eq(stats.health, 50)

func test_a_maximum_of_zero_is_treated_as_one() -> void:
	stats.max_health = 0
	stats.reset()
	assert_eq(stats.health, 1)
	assert_false(stats.is_dead())
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`. Expected: script errors for `StatusEffect` and the new methods.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 20 new.
- [ ] **Step 5: Commit** — `feat: add timed effects, hits through Unit and revival`

---

### Task 3: One combat brain for enemies and companions

**Files:**
- Create: `src/units/combat_brain.gd`, `tests/units/test_combat_brain.gd`
- Delete: `src/units/enemy_brain.gd`, `tests/units/test_enemy_brain.gd` (its four tests move into the new file unchanged apart from the helper)
- Modify: `scenes/units/crusader.tscn`, `src/core/probe.gd` (class name only), `tests/units/test_chase.gd` only if it names `EnemyBrain`

**Interfaces:**
- Consumes: `Unit.current_order()`, `order_attack`, `order_move`, `attack_target()`, `is_stunned()`, `taunt_radius()`.
- Produces: `class_name CombatBrain extends Node` (child of a `Unit`, node name `Brain`)
  - `@export var aggro_radius: float = 8.0`, `@export var think_interval: float = 0.25`, `@export var switch_margin: float = 2.0`, `@export var follow_distance: float = 3.0`
  - `var enabled: bool = true`, `var leader: Unit`. Setting `enabled` to false stops a follow walk the brain started; an attack the brain started carries on.
  - Each think, when enabled and its unit is alive and not stunned, the first rule that applies wins:
    1. **Taunt.** If a living hostile's `taunt_radius()` reaches this unit, attack the nearest such hostile, whatever the unit was doing.
    2. **Leave the player's orders alone.** If the unit has an order the brain did not give (`current_order() != NONE` and the attack target is not one the brain chose), do nothing.
    3. **Reconsider.** If the unit is attacking a target the brain chose and another living hostile is nearer by more than `switch_margin`, attack that one.
    4. **Engage.** If idle and a living hostile is within `aggro_radius`, attack the nearest.
    5. **Follow.** If idle, `leader` is alive and farther than `follow_distance + 1.0`, walk to a point `follow_distance` short of the leader. A follow walk is the brain's own order: rule 2 does not protect it, so rules 1, 3 and 4 interrupt it.
  - All distances flat on XZ.

- [ ] **Step 1: Write the failing tests** (4 moved + 8 new)

Move the four tests of `test_enemy_brain.gd` into `tests/units/test_combat_brain.gd` with the same names and assertions, built on `Arena` (`arena.spawn(Arena.CRUSADER, at, true)` keeps the brain). Then add:

```gdscript
func test_switches_to_a_much_nearer_hostile() -> void:
	# foe has engaged alvar on its own; a second player unit appears right beside it
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	var second: Unit = arena.spawn(Arena.ALVAR, foe.global_position + Vector3(0.8, 0, 0))
	alvar.global_position = Vector3(1, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), second)

func test_keeps_its_target_when_the_other_is_only_slightly_nearer() -> void:
	alvar.global_position = Vector3(4, 0, 8)
	await wait_seconds(0.6)
	var second: Unit = arena.spawn(Arena.ALVAR, Vector3(4.5, 0, 8))
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_a_taunt_overrides_everything() -> void:
	alvar.global_position = Vector3(6, 0, 8)
	await wait_seconds(0.6)
	var tank: Unit = arena.spawn(Arena.ALVAR, Vector3(1, 0, 8))
	var taunt := StatusEffect.new()
	taunt.id = &"taunt"
	taunt.duration = 5.0
	taunt.taunt_radius = 8.0
	tank.add_effect(taunt)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), tank)

func test_a_disabled_brain_does_nothing() -> void:
	(foe.get_node("Brain") as CombatBrain).enabled = false
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_disabling_stops_a_follow_walk_but_not_a_fight() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	var brain := friend.get_node("Brain") as CombatBrain
	brain.leader = foe
	await wait_seconds(0.8)
	assert_true(friend.is_moving())
	brain.enabled = false
	assert_false(friend.is_moving())
	brain.enabled = true
	alvar.global_position = friend.global_position + Vector3(2, 0, 0)
	await wait_seconds(0.6)
	brain.enabled = false
	assert_eq(friend.attack_target(), alvar)

func test_leaves_an_order_it_did_not_give() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	foe.order_move(Vector3(8, 0, -8))
	await wait_seconds(0.6)
	assert_eq(foe.current_order(), Unit.Order.MOVE)
	assert_null(foe.attack_target())

func test_follows_its_leader_when_idle() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = foe
	await wait_seconds(5.0)
	assert_lt(Arena.flat(friend.global_position, foe.global_position), 4.5)
	assert_gt(Arena.flat(friend.global_position, foe.global_position), 1.5)

func test_a_follower_breaks_off_to_fight() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = foe
	alvar.global_position = Vector3(-6, 0, 6)
	await wait_seconds(0.8)
	assert_eq(friend.attack_target(), alvar)
```

`before_each` for this file: `alvar` at (−8, 0, −8), `foe` (crusader with brain) at (8, 0, 8), as in the old file.

- [ ] **Step 2: Run to verify failure.** — `ops/test.sh`. Expected: script error for `CombatBrain`.
- [ ] **Step 3: Implement `CombatBrain`; delete `EnemyBrain`; point the crusader scene and `Probe` at the new class.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass; this file has 12.
- [ ] **Step 5: Commit** — `feat: replace the enemy brain with one combat brain for all units`

---

### Task 4: The party in the room

**Files:**
- Create: `scenes/units/zahra.tscn`, `scenes/units/gonzalo.tscn`, `tests/core/test_party.gd`
- Modify: `src/main.gd`, `scenes/main.tscn`, `scenes/rooms/vault_room.tscn`, `scenes/units/alvar.tscn`, `tests/core/test_main.gd` (one test, named below), `tests/core/test_near_wall_clicks.gd` only where it assumes three enemies, `tests/support/arena.gd` (add `ZAHRA`, `GONZALO` constants)

**Interfaces:**
- Produces: unit scenes inheriting `unit_base.tscn`, all `faction = &"player"`, each with a `Brain` (`CombatBrain`):

| Scene | `display_name` | `max_health` | `starting_blood` | `move_speed` | Melee damage / cooldown | Body colour |
|---|---|---|---|---|---|---|
| `alvar.tscn` | Brother Álvar | 120 | 60 | 4.0 | 15 / 0.9 | off-white |
| `zahra.tscn` | Zahra | 80 | 60 | 4.0 | 8 / 1.0 | teal |
| `gonzalo.tscn` | Gonzalo | 160 | 60 | 3.4 | 18 / 1.3 | slate grey |

  `alvar.tscn` gains `starting_blood = 60` and a `Brain`.
- Produces, in `vault_room.tscn`: markers `CompanionSpawn1` (−10, y, 1.5) and `CompanionSpawn2` (−10, y, −1.5) at the same height as `PlayerSpawn`; enemy markers `EnemySpawn1`…`EnemySpawn3` moved to a first group around x = 0 and `EnemySpawn4`…`EnemySpawn6` added as a second group around x = 9, each on the navmesh, none inside a pillar, at least 1 m apart.
- Produces, on `Main`:
  - `var party: Array[Unit]` (Álvar, Zahra, Gonzalo, in that order), `var selected: Unit`; `player` stays and is `party[0]`
  - `signal selection_changed(unit: Unit)`, `signal room_cleared`, `signal party_changed` (a member fell or rose)
  - `func select(unit: Unit) -> void` — ignored unless `unit` is a living party member. Sets `selected`, `rig.target` (no snap), `input.unit`; the selected unit's brain is disabled (which stops a follow walk, Task 3); every other living member's brain is enabled with `leader = selected`. Emits `selection_changed`.
  - `func select_next() -> void` — next living member after `selected`, wrapping.
  - When the selected member dies and it is not Álvar, `select(player)`.
  - **Fight flow.** `func fight_is_on() -> bool` is true while any living enemy has an attack target. `@export var calm_time: float = 3.0`: once `fight_is_on()` has been false for `calm_time`, every fallen companion is revived (`revive()`, 30 % health). When `enemies_alive()` reaches 0, `room_cleared` is emitted once per round and fallen companions rise at once.
  - Álvar's fall still disables input and shows the prompt; `confirm` restarts. `start_room()` builds the whole party afresh and selects Álvar.
- Changes `tests/core/test_main.gd`: `test_the_room_starts_with_one_player_and_three_enemies` is renamed `test_the_room_starts_with_the_party_and_six_enemies` and asserts `main.party.size() == 3`, `main.enemies_alive() == 6`, `main.input.enabled`; `test_confirm_after_falling_restarts_the_room` asserts 6. `test_every_spawn_point_is_on_the_navmesh` adds the new marker names.

- [ ] **Step 1: Write the failing tests** (9 tests)

```gdscript
# tests/core/test_party.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)

func _brain(unit: Unit) -> CombatBrain:
	return unit.get_node("Brain") as CombatBrain

func _kill_enemies() -> void:
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)

func test_the_party_is_alvar_zahra_and_gonzalo_with_alvar_selected() -> void:
	assert_eq(main.party.map(func(u: Unit) -> String: return u.display_name), ["Brother Álvar", "Zahra", "Gonzalo"])
	assert_eq(main.selected, main.player)
	assert_eq(main.player.stats.blood, 60)

func test_selecting_hands_over_camera_input_and_brains() -> void:
	watch_signals(main)
	var zahra: Unit = main.party[1]
	main.select(zahra)
	assert_eq(main.selected, zahra)
	assert_eq(main.rig.target, zahra)
	assert_eq(main.input.unit, zahra)
	assert_false(_brain(zahra).enabled)
	assert_true(_brain(main.player).enabled)
	assert_eq(_brain(main.player).leader, zahra)
	assert_signal_emitted_with_parameters(main, "selection_changed", [zahra])

func test_select_next_cycles_and_skips_the_fallen() -> void:
	main.party[1].take_hit(999)
	main.select_next()
	assert_eq(main.selected, main.party[2])
	main.select_next()
	assert_eq(main.selected, main.party[0])

func test_an_enemy_or_a_fallen_member_cannot_be_selected() -> void:
	main.select(main.enemies[0])
	assert_eq(main.selected, main.player)
	main.party[2].take_hit(999)
	main.select(main.party[2])
	assert_eq(main.selected, main.player)

func test_selection_returns_to_alvar_when_the_selected_companion_falls() -> void:
	main.select(main.party[1])
	main.party[1].take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.selected, main.player)
	assert_eq(main.rig.target, main.player)

func test_companions_follow_the_selected_member() -> void:
	_kill_enemies()  # nothing to fight, so following is all they do
	main.player.order_move(Vector3(-2, 0, 0))
	await wait_seconds(4.0)
	for companion: Unit in [main.party[1], main.party[2]]:
		assert_lt(Arena.flat(companion.global_position, main.player.global_position), 5.0, companion.display_name)
		assert_gt(companion.global_position.x, -8.0, companion.display_name)

func test_a_fallen_companion_rises_when_the_fight_has_been_calm() -> void:
	main.calm_time = 0.5
	main.party[1].take_hit(999)
	await wait_seconds(1.0)
	assert_true(main.party[1].is_alive())
	assert_eq(main.party[1].stats.health, 24)  # 30% of 80

func test_clearing_the_room_signals_once_and_raises_the_fallen() -> void:
	watch_signals(main)
	main.party[2].take_hit(999)
	_kill_enemies()
	await wait_physics_frames(3)
	assert_signal_emit_count(main, "room_cleared", 1)
	assert_true(main.party[2].is_alive())

func test_alvar_falling_ends_the_round_and_restart_rebuilds_the_party() -> void:
	main.select(main.party[1])
	main.party[2].take_hit(999)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(main.hud.is_fallen_shown())
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_eq(main.party.size(), 3)
	for member: Unit in main.party:
		assert_true(member.is_alive())
		assert_eq(member.stats.health, member.stats.max_health)
	assert_eq(main.selected, main.player)
	assert_eq(main.enemies_alive(), 6)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`. Expected: load errors for the new scenes and members.
- [ ] **Step 3: Build the scenes, the markers and the `Main` changes.** While Álvar is down the companions' brains keep running; nothing revives until restart.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 9 new, the renamed test green.
- [ ] **Step 5: Look at it.** Capture one frame at spawn (`godot --path . --write-movie build/shots/party.png --quit-after 60 --fixed-fps 30`) and read it: three distinct party colours at the west end, the first enemy group visible further east.
- [ ] **Step 6: Commit** — `feat: add Zahra and Gonzalo and a selectable party of three`

---

### Task 5: Picking, selection by mouse and keys, and pause

**Files:**
- Create: `src/player/picker.gd`, `tests/player/test_picker.gd`, `tests/core/test_pause_and_selection_input.gd`
- Modify: `src/player/player_input.gd`, `src/main.gd`, `scenes/main.tscn`, `project.godot`

**Interfaces:**
- Produces: `class_name Picker extends RefCounted`
  - `static func unit_at(camera: Camera3D, screen: Vector2) -> Unit` — first body on layer 2 under the point, or null.
  - `static func ground_at(camera: Camera3D, screen: Vector2) -> Variant` — the hit point on layer 1, else the ray's meeting point with the plane Y = 0, else null.
  - Neither tests layer 3.
- Changes `PlayerInput`:
  - `signal select_requested(unit: Unit)`, `signal select_next_requested`
  - `click_at(screen)`: a living unit of the controlled unit's faction other than itself → `select_requested`; a living hostile → `order_attack`; otherwise the ground point → `order_move`. Clicking the controlled unit itself does nothing.
  - Action `select_next` pressed → `select_next_requested`. `PlayerInput` never calls `Main`.
  - Camera wheel and Q/E keep working whatever `enabled` is.
- Input map: `select_next` = Tab; `pause` = Space; `confirm` = Enter only (Space removed).
- Produces, on `Main`:
  - `func set_paused(on: bool) -> void`, `func is_paused() -> bool`, `signal pause_changed(paused: bool)`. Pausing sets the units container's `process_mode` to `PROCESS_MODE_DISABLED`, unpausing to `PROCESS_MODE_INHERIT`. `SceneTree.paused` is never touched. Orders given while paused are stored by the units and begin on unpause.
  - The `pause` action toggles it, polled like `confirm`. Pause is refused while Álvar is down; `start_room()` unpauses.
  - `Main` connects `input.select_requested` to `select` and `input.select_next_requested` to `select_next`.

- [ ] **Step 1: Write the failing tests** (5 + 9 tests)

```gdscript
# tests/player/test_picker.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit
var cam: Camera3D

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, -4))
	var rig := CameraRig.new()
	cam = Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	arena.room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return cam.unproject_position(world)

func test_finds_the_unit_under_the_point() -> void:
	assert_eq(Picker.unit_at(cam, _screen(foe.global_position + Vector3(0, 0.9, 0))), foe)

func test_finds_no_unit_over_bare_floor() -> void:
	assert_null(Picker.unit_at(cam, _screen(Vector3(4, 0, 2))))

func test_a_fallen_unit_is_not_picked() -> void:
	foe.take_hit(999)
	await wait_physics_frames(3)
	assert_null(Picker.unit_at(cam, _screen(foe.global_position + Vector3(0, 0.3, 0))))

func test_ground_under_a_unit_is_still_ground() -> void:
	var point: Vector3 = Picker.ground_at(cam, _screen(foe.global_position + Vector3(0, 0.9, 0)))
	assert_almost_eq(point.y, 0.0, 0.05)

func test_ground_beyond_the_floor_falls_back_to_the_plane() -> void:
	var point: Variant = Picker.ground_at(cam, Vector2(640, 2))
	assert_not_null(point)
	assert_almost_eq((point as Vector3).y, 0.0, 0.01)
```

```gdscript
# tests/core/test_pause_and_selection_input.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return main.rig.camera().unproject_position(world)

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)

func test_clicking_a_companion_selects_it() -> void:
	var zahra: Unit = main.party[1]
	main.input.click_at(_screen(zahra.global_position + Vector3(0, 0.9, 0)))
	assert_eq(main.selected, zahra)

func test_clicking_the_selected_unit_gives_no_order() -> void:
	main.input.click_at(_screen(main.player.global_position + Vector3(0, 0.9, 0)))
	assert_eq(main.player.current_order(), Unit.Order.NONE)
	assert_eq(main.selected, main.player)

func test_tab_selects_the_next_member() -> void:
	await _tap(&"select_next")
	assert_eq(main.selected, main.party[1])

func test_space_pauses_and_unpauses() -> void:
	watch_signals(main)
	await _tap(&"pause")
	assert_true(main.is_paused())
	assert_signal_emitted_with_parameters(main, "pause_changed", [true])
	await _tap(&"pause")
	assert_false(main.is_paused())

func test_space_no_longer_confirms() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	await _tap(&"pause")
	assert_false(main.player.is_alive())
	assert_false(main.is_paused())

func test_nothing_moves_while_paused_and_orders_wait() -> void:
	main.set_paused(true)
	var from: Vector3 = main.player.global_position
	main.player.order_move(from + Vector3(4, 0, 0))
	await wait_seconds(0.5)
	assert_lt(Arena.flat(main.player.global_position, from), 0.05)
	main.set_paused(false)
	await wait_for_signal(main.player.arrived, 4.0)
	assert_lt(Arena.flat(main.player.global_position, from + Vector3(4, 0, 0)), 0.5)

func test_selection_and_camera_work_while_paused() -> void:
	main.set_paused(true)
	main.select(main.party[2])
	assert_eq(main.selected, main.party[2])
	var yaw: float = main.rig.rotation.y
	main.rig.rotate_by(0.5)
	assert_almost_eq(main.rig.rotation.y, yaw + 0.5, 0.001)

func test_effects_and_cooldowns_do_not_run_while_paused() -> void:
	var effect := StatusEffect.new()
	effect.id = &"test"
	effect.duration = 0.3
	main.player.add_effect(effect)
	main.set_paused(true)
	await wait_seconds(0.6)
	assert_true(main.player.has_effect(&"test"))

func test_restart_unpauses() -> void:
	main.set_paused(true)
	main.start_room()
	assert_false(main.is_paused())
	assert_eq(main.selected, main.player)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`. Expected: errors for `Picker`, the new actions and methods.
- [ ] **Step 3: Implement.** `PlayerInput.click_at` uses `Picker`; its own ray code goes.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 14 new; `test_player_input.gd` and `test_near_wall_clicks.gd` unchanged and green.
- [ ] **Step 5: Commit** — `feat: add click and Tab selection and a world pause on Space`

---

### Task 6: Blood, feeding and the Fury

**Files:**
- Create: `tests/units/test_feeding.gd`, `tests/units/test_fury.gd`
- Modify: `src/units/unit.gd`, `src/player/player_input.gd`, `src/units/combat_brain.gd`, `scenes/units/alvar.tscn`, `zahra.tscn`, `gonzalo.tscn`

**Interfaces:**
- Produces, on `Unit`:
  - `@export var drinks_blood: bool = false` (true in the three party scenes), `@export var feed_threshold: float = 0.35`, `@export var feed_time: float = 2.0`, `@export var feed_gain: int = 40`
  - `Order.FEED` added to the enum. `signal fed(target: Unit)`, `signal feed_broken`
  - `func can_be_fed_on() -> bool` — alive and `health <= max_health * feed_threshold` (the unit's own threshold is not used here: the feeder's is; give this method a `threshold: float` parameter if cleaner, as long as `can_feed_on` below is the public test).
  - `func can_feed_on(target: Unit) -> bool` — this unit is alive, drinks blood, is not in the Fury; `target` is alive, hostile, and at or below `feed_threshold` of its maximum health.
  - `func order_feed(target: Unit) -> void` — ignored unless `can_feed_on(target)`. The unit closes to melee range, then feeds for `feed_time`: `is_feeding()` is true, it neither walks nor strikes, and the target carries a stunning effect `&"fed_on"` for as long as the feed lasts. On completion the target dies by a hit for its remaining health from the feeder, the feeder gains `feed_gain` Blood, emits `fed(target)`, order `NONE`.
  - A feed is broken, with no Blood gained, the `&"fed_on"` effect removed and `feed_broken` emitted, when: the feeder is stunned or dies, the target dies or is freed by other means, or the feeder receives any new order or `stop()`.
  - `@export var fury_threshold: int = 10`, `@export var fury_time: float = 5.0`, `@export var fury_damage: float = 1.5`; `signal fury_started`, `signal fury_ended`; `func is_in_fury() -> bool`
  - **The Fury** starts when a blood-drinking unit's Blood falls below `fury_threshold` by being spent (a `blood_changed` to a lower value that crosses the threshold; starting a round below it does not count). For `fury_time` the unit carries effect `&"fury"` (`damage_dealt_multiplier = fury_damage`), ignores every `order_*` call and `stop()`, and attacks the nearest living unit of any faction, choosing again whenever its target dies. A feed in progress is broken. When it ends: order `NONE`, `fury_ended`.
- Changes `PlayerInput.click_at`: a click on a living hostile that the controlled unit `can_feed_on` and whose own Blood is below its maximum → `order_feed`; otherwise attack as before.
- Changes `CombatBrain`: it does nothing while its unit is feeding or in the Fury.

- [ ] **Step 1: Write the failing tests** (9 + 7 tests)

```gdscript
# tests/units/test_feeding.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func test_only_a_weakened_enemy_can_be_fed_on() -> void:
	assert_false(alvar.can_feed_on(foe))
	foe.take_hit(39)  # 21 of 60 = 35%
	assert_true(alvar.can_feed_on(foe))

func test_mortals_do_not_feed_and_friends_are_not_food() -> void:
	alvar.take_hit(100)  # 20 of 120
	assert_false(foe.can_feed_on(alvar))
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(2, 0, 0))
	friend.take_hit(100)
	assert_false(alvar.can_feed_on(friend))

func test_a_full_feed_kills_the_target_and_gives_blood() -> void:
	watch_signals(alvar)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.5)
	assert_true(alvar.is_feeding())
	assert_true(foe.is_stunned())
	assert_eq(alvar.current_order(), Unit.Order.FEED)
	await wait_seconds(2.0)
	assert_false(foe.is_alive())
	assert_eq(alvar.stats.blood, 100)  # 60 + 40
	assert_signal_emitted_with_parameters(alvar, "fed", [foe])
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_blood_gained_is_capped_at_the_maximum() -> void:
	alvar.stats.gain_blood(30)  # 90
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(2.6)
	assert_eq(alvar.stats.blood, 100)

func test_the_feeder_walks_to_a_distant_target_first() -> void:
	foe.global_position = Vector3(0, 0, 6)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_for_signal(alvar.fed, 8.0)
	assert_false(foe.is_alive())

func test_a_new_order_breaks_the_feed_and_frees_the_target() -> void:
	watch_signals(alvar)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	alvar.order_move(Vector3(4, 0, 0))
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_false(foe.is_stunned())
	assert_true(foe.is_alive())
	assert_eq(alvar.stats.blood, 60)
	assert_signal_emitted(alvar, "feed_broken")

func test_a_stun_breaks_the_feed() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	alvar.add_effect(stun)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_false(foe.has_effect(&"fed_on"))

func test_a_target_killed_by_another_ends_the_feed_without_blood() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.take_hit(999)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_target_freed_mid_feed_causes_no_error() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.free()
	await wait_physics_frames(5)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)
```

```gdscript
# tests/units/test_fury.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	await wait_physics_frames(3)

func test_spending_below_the_threshold_starts_the_fury() -> void:
	watch_signals(alvar)
	alvar.stats.spend_blood(45)  # 15
	assert_false(alvar.is_in_fury())
	alvar.stats.spend_blood(10)  # 5
	assert_true(alvar.is_in_fury())
	assert_signal_emit_count(alvar, "fury_started", 1)
	assert_true(alvar.has_effect(&"fury"))
	assert_almost_eq(alvar.damage_dealt_multiplier(), 1.5, 0.001)

func test_mortals_have_no_fury() -> void:
	foe.stats.spend_blood(95)
	assert_false(foe.is_in_fury())

func test_the_fury_attacks_the_nearest_unit_friend_or_foe() -> void:
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(2, 0, 0))
	await wait_physics_frames(2)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	assert_eq(alvar.attack_target(), friend)

func test_orders_are_ignored_in_the_fury() -> void:
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	alvar.order_move(Vector3(-8, 0, -8))
	alvar.stop()
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	assert_eq(alvar.attack_target(), foe)

func test_the_fury_ends_after_its_time_and_leaves_the_unit_idle() -> void:
	alvar.fury_time = 0.6
	watch_signals(alvar)
	alvar.stats.spend_blood(55)
	await wait_seconds(1.0)
	assert_false(alvar.is_in_fury())
	assert_signal_emitted(alvar, "fury_ended")
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	alvar.order_move(Vector3(-3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)

func test_the_fury_moves_on_when_its_target_dies() -> void:
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(1.2, 0, 0))
	await wait_physics_frames(2)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	friend.take_hit(999)
	await wait_physics_frames(5)
	assert_eq(alvar.attack_target(), foe)

func test_falling_further_while_already_in_the_fury_does_not_restart_it() -> void:
	watch_signals(alvar)
	alvar.stats.spend_blood(52)  # 8
	alvar.stats.spend_blood(5)   # 3
	assert_signal_emit_count(alvar, "fury_started", 1)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.** If `unit.gd` would pass about 300 lines, stop and report DONE_WITH_CONCERNS with a proposed split (feeding and the Fury as child nodes) rather than splitting unasked.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 16 new.
- [ ] **Step 5: Commit** — two commits: `feat: let the party feed on weakened enemies for Blood`, `feat: add the Fury when Blood is spent too low`

---

### Task 7: Gifts and Álvar's two

**Files:**
- Create: `src/gifts/gift.gd`, `src/gifts/gift_user.gd`, `src/gifts/iron_sinew.gd`, `src/gifts/baleful_eye.gd`, `resources/gifts/iron_sinew.tres`, `resources/gifts/baleful_eye.tres`, `tests/gifts/test_gift_user.gd`, `tests/gifts/test_alvar_gifts.gd`
- Modify: `scenes/units/alvar.tscn`

**Interfaces:**
- Produces: `class_name Gift extends Resource`
  - `enum Targeting { SELF, ENEMY, ALLY }`
  - `@export var id: StringName`, `@export var display_name: String`, `@export var blood_cost: int = 0`, `@export var cooldown: float = 0.0`, `@export var targeting: Targeting = Targeting.SELF`, `@export var cast_range: float = 0.0`
  - `func can_target(caster: Unit, target: Unit) -> bool` — `SELF`: true, the target is ignored. `ENEMY`: target valid, alive, hostile to the caster, within `cast_range`. `ALLY`: target valid, alive, not hostile (the caster counts), within `cast_range`.
  - `func apply(caster: Unit, target: Unit) -> void` — overridden by each Gift; the base does `push_error`.
- Produces: `class_name GiftUser extends Node` (child of a `Unit`, node name `Gifts`)
  - `@export var gifts: Array[Gift]`; `signal gift_used(index: int, target: Unit)`, `signal cooldowns_changed`
  - `func count() -> int`, `func gift(index: int) -> Gift` (null when out of range), `func cooldown_left(index: int) -> float`
  - `func can_use(index: int, target: Unit = null) -> bool` — the index exists; the unit is alive, not stunned, not feeding, not in the Fury; the cooldown is over; `stats.blood >= blood_cost`; `can_target` holds.
  - `func use(index: int, target: Unit = null) -> bool` — when `can_use`: spends the Blood, starts the cooldown, calls `apply`, emits `gift_used`; returns whether it was used. The Blood is spent before `apply`, so a Gift that takes Blood under the Fury threshold takes effect and then the Fury begins.
  - `func reset_cooldowns() -> void`. Cooldowns run in `_physics_process`, so they stop with the world pause.
- Produces the two Gifts, each a script extending `Gift` with its own exported numbers and a `.tres`:

| Gift (`id`) | Class | Targeting | Range | Cost | Cooldown | Effect |
|---|---|---|---|---|---|---|
| Iron Sinew (`iron_sinew`) | `IronSinew` | SELF | — | 20 | 12 | effect `&"iron_sinew"` on the caster for `duration = 8.0`: `speed_multiplier = 1.4`, `damage_dealt_multiplier = 1.5` |
| Baleful Eye (`baleful_eye`) | `BalefulEye` | ENEMY | 8 | 15 | 10 | effect `&"baleful_eye"` on the target for `duration = 4.0`: `stuns = true` |

- `alvar.tscn` gains `Gifts` with Iron Sinew then Baleful Eye.

- [ ] **Step 1: Write the failing tests** (9 + 4 tests)

```gdscript
# tests/gifts/test_gift_user.gd
extends GutTest

## A Gift that records what it was applied to.
class Marker extends Gift:
	var applied: Array = []
	func apply(caster: Unit, target: Unit) -> void:
		applied.append([caster, target])

var arena: Arena
var alvar: Unit
var foe: Unit
var gifts: GiftUser
var marker: Marker

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	gifts = alvar.get_node("Gifts")
	marker = Marker.new()
	marker.id = &"marker"
	marker.blood_cost = 20
	marker.cooldown = 0.5
	marker.targeting = Gift.Targeting.ENEMY
	marker.cast_range = 8.0
	gifts.gifts = [marker]
	await wait_physics_frames(3)

func test_using_a_gift_spends_blood_applies_it_and_starts_the_cooldown() -> void:
	watch_signals(gifts)
	assert_true(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 40)
	assert_eq(marker.applied, [[alvar, foe]])
	assert_gt(gifts.cooldown_left(0), 0.0)
	assert_signal_emitted_with_parameters(gifts, "gift_used", [0, foe])

func test_no_use_during_the_cooldown_and_again_after_it() -> void:
	gifts.use(0, foe)
	assert_false(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 40)
	await wait_seconds(0.7)
	assert_true(gifts.use(0, foe))

func test_too_little_blood_refuses_and_costs_nothing() -> void:
	alvar.stats.spend_blood(45)  # 15
	assert_false(gifts.can_use(0, foe))
	assert_false(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 15)
	assert_eq(marker.applied.size(), 0)

func test_a_gift_may_take_blood_into_the_fury() -> void:
	alvar.stats.spend_blood(35)  # 25
	assert_true(gifts.use(0, foe))  # 5
	assert_eq(marker.applied.size(), 1)
	assert_true(alvar.is_in_fury())
	assert_false(gifts.can_use(0, foe))

func test_enemy_gifts_need_a_living_hostile_in_range() -> void:
	assert_false(gifts.can_use(0, null))
	assert_false(gifts.can_use(0, alvar))
	foe.global_position = Vector3(0, 0, 9)
	assert_false(gifts.can_use(0, foe))
	foe.global_position = Vector3(0, 0, 5)
	foe.take_hit(999)
	assert_false(gifts.can_use(0, foe))

func test_ally_gifts_accept_the_caster_and_friends_only() -> void:
	marker.targeting = Gift.Targeting.ALLY
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(3, 0, 0))
	assert_true(gifts.can_use(0, alvar))
	assert_true(gifts.can_use(0, friend))
	assert_false(gifts.can_use(0, foe))

func test_self_gifts_need_no_target() -> void:
	marker.targeting = Gift.Targeting.SELF
	assert_true(gifts.use(0))
	assert_eq(marker.applied, [[alvar, null]])

func test_a_stunned_or_dead_caster_cannot_use_gifts() -> void:
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 5.0
	stun.stuns = true
	alvar.add_effect(stun)
	assert_false(gifts.can_use(0, foe))
	alvar.clear_effects()
	alvar.take_hit(999)
	assert_false(gifts.can_use(0, foe))

func test_an_index_out_of_range_is_refused() -> void:
	assert_null(gifts.gift(3))
	assert_false(gifts.use(3, foe))
	assert_false(gifts.use(-1, foe))
```

```gdscript
# tests/gifts/test_alvar_gifts.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit
var gifts: GiftUser

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	gifts = alvar.get_node("Gifts")
	await wait_physics_frames(3)

func test_alvar_carries_iron_sinew_and_baleful_eye() -> void:
	assert_eq(gifts.count(), 2)
	assert_eq([gifts.gift(0).display_name, gifts.gift(1).display_name], ["Iron Sinew", "Baleful Eye"])
	assert_eq([gifts.gift(0).blood_cost, gifts.gift(1).blood_cost], [20, 15])
	assert_eq([gifts.gift(0).cooldown, gifts.gift(1).cooldown], [12.0, 10.0])

func test_iron_sinew_makes_him_faster_and_stronger() -> void:
	assert_true(gifts.use(0))
	assert_true(alvar.has_effect(&"iron_sinew"))
	assert_almost_eq(alvar.speed_multiplier(), 1.4, 0.001)
	assert_almost_eq(alvar.damage_dealt_multiplier(), 1.5, 0.001)
	assert_eq(alvar.stats.blood, 40)

func test_baleful_eye_stuns_an_enemy_in_range() -> void:
	assert_true(gifts.use(1, foe))
	assert_true(foe.is_stunned())
	assert_eq(alvar.stats.blood, 45)

func test_baleful_eye_does_not_reach_past_eight_metres() -> void:
	foe.global_position = Vector3(0, 0, 8.5)
	assert_false(gifts.use(1, foe))
	assert_eq(alvar.stats.blood, 60)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 13 new.
- [ ] **Step 5: Commit** — `feat: add the Gift system with Iron Sinew and Baleful Eye`

---

### Task 8: Zahra's and Gonzalo's Gifts

**Files:**
- Create: `src/gifts/mend_flesh.gd`, `blood_lance.gd`, `stone_hide.gd`, `hammerfall.gd`, their four `.tres` files in `resources/gifts/`, `tests/gifts/test_companion_gifts.gd`
- Modify: `scenes/units/zahra.tscn`, `scenes/units/gonzalo.tscn`

**Interfaces:**
- Consumes: `Gift`, `GiftUser`, `StatusEffect`, `Unit.take_hit`, `CombatBrain` rule 1 (taunt).
- Produces:

| Gift (`id`) | Class | Carried by | Targeting | Range | Cost | Cooldown | Effect |
|---|---|---|---|---|---|---|---|
| Mend Flesh (`mend_flesh`) | `MendFlesh` | Zahra, slot 1 | ALLY | 8 | 20 | 6 | `target.stats.heal(amount)`, `amount = 40` |
| Blood Lance (`blood_lance`) | `BloodLance` | Zahra, slot 2 | ENEMY | 10 | 15 | 4 | `target.take_hit(damage, caster)`, `damage = 30` |
| Stone Hide (`stone_hide`) | `StoneHide` | Gonzalo, slot 1 | SELF | — | 20 | 15 | effect `&"stone_hide"` for `duration = 8.0`: `damage_taken_multiplier = 0.4`, `taunt_radius = 8.0` |
| Hammerfall (`hammerfall`) | `Hammerfall` | Gonzalo, slot 2 | SELF | — | 25 | 12 | every living hostile within `radius = 3.5` takes `take_hit(damage, caster)` with `damage = 15` and effect `&"hammerfall"` for `stun_time = 2.5`: `stuns = true` |

- [ ] **Step 1: Write the failing tests** (8 tests)

```gdscript
# tests/gifts/test_companion_gifts.gd
extends GutTest

var arena: Arena
var zahra: Unit
var gonzalo: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	zahra = arena.spawn(Arena.ZAHRA, Vector3.ZERO)
	gonzalo = arena.spawn(Arena.GONZALO, Vector3(2, 0, 0))
	foe = arena.spawn(Arena.CRUSADER, Vector3(2, 0, 2))
	await wait_physics_frames(3)

func _gifts(unit: Unit) -> GiftUser:
	return unit.get_node("Gifts")

func test_each_companion_carries_two_gifts_in_order() -> void:
	assert_eq([_gifts(zahra).gift(0).display_name, _gifts(zahra).gift(1).display_name], ["Mend Flesh", "Blood Lance"])
	assert_eq([_gifts(gonzalo).gift(0).display_name, _gifts(gonzalo).gift(1).display_name], ["Stone Hide", "Hammerfall"])

func test_mend_flesh_heals_an_ally_up_to_the_maximum() -> void:
	gonzalo.take_hit(60)  # 100 of 160
	assert_true(_gifts(zahra).use(0, gonzalo))
	assert_eq(gonzalo.stats.health, 140)
	assert_eq(zahra.stats.blood, 40)

func test_mend_flesh_cannot_raise_the_fallen_or_help_an_enemy() -> void:
	gonzalo.take_hit(999)
	assert_false(_gifts(zahra).use(0, gonzalo))
	assert_false(_gifts(zahra).use(0, foe))
	assert_eq(zahra.stats.blood, 60)

func test_blood_lance_wounds_at_range() -> void:
	foe.global_position = Vector3(0, 0, 9)
	watch_signals(foe)
	assert_true(_gifts(zahra).use(1, foe))
	assert_eq(foe.stats.health, 30)
	assert_signal_emitted_with_parameters(foe, "was_hit", [30, zahra])

func test_stone_hide_hardens_gonzalo() -> void:
	assert_true(_gifts(gonzalo).use(0))
	assert_eq(gonzalo.take_hit(10), 4)
	assert_eq(gonzalo.taunt_radius(), 8.0)

func test_stone_hide_draws_an_enemy_off_another_target() -> void:
	var hunter: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 3), true)
	await wait_seconds(0.6)
	assert_eq(hunter.attack_target(), zahra)
	_gifts(gonzalo).use(0)
	await wait_seconds(0.6)
	assert_eq(hunter.attack_target(), gonzalo)

func test_hammerfall_hits_and_stuns_enemies_around_him_only() -> void:
	var far: Unit = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 0))
	assert_true(_gifts(gonzalo).use(1))
	assert_eq(foe.stats.health, 45)
	assert_true(foe.is_stunned())
	assert_eq(far.stats.health, 60)
	assert_false(far.is_stunned())
	assert_eq(zahra.stats.health, 80)
	assert_false(zahra.is_stunned())

func test_hammerfall_with_nobody_near_still_costs_blood() -> void:
	foe.global_position = Vector3(9, 0, 9)
	assert_true(_gifts(gonzalo).use(1))
	assert_eq(gonzalo.stats.blood, 35)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement the four Gifts and add `Gifts` to both scenes.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 8 new.
- [ ] **Step 5: Commit** — `feat: add Mend Flesh, Blood Lance, Stone Hide and Hammerfall`

---

### Task 9: Gift keys, targeting and companions who use their Gifts

**Files:**
- Create: `tests/player/test_gift_input.gd`, `tests/units/test_companion_behaviour.gd`
- Modify: `src/player/player_input.gd`, `src/units/combat_brain.gd`, `src/main.gd`, `project.godot`, `scenes/units/zahra.tscn`, `gonzalo.tscn`, `alvar.tscn`

**Interfaces:**
- Input map: `gift_1` = key 1, `gift_2` = key 2, `cancel` = Escape.
- Produces, on `PlayerInput`:
  - `signal targeting_changed(index: int)` (−1 when none), `func targeting_gift() -> int`
  - `func press_gift(index: int) -> void` — for the controlled unit's `Gifts`: a `SELF` Gift is used at once. A targeted Gift that `can_use` apart from its target (alive, free to act, off cooldown, enough Blood) opens targeting for that index; one that cannot is ignored. Pressing the same index again closes targeting.
  - While targeting, `click_at` on a unit the Gift can target uses it and closes targeting; a click on anything else leaves targeting open and gives no order. `func cancel_targeting() -> void`; the `cancel` action and a right mouse click call it. Changing `unit` (selection) closes targeting.
  - The `gift_1` / `gift_2` actions call `press_gift(0)` / `press_gift(1)`, and work while paused. A Gift used while paused takes effect at once (its Blood is spent, its effect applied); its timers start on unpause.
  - When `enabled` is false, Gift keys do nothing and targeting closes.
- `Main.start_room()` closes targeting; so does Álvar's fall.
- Produces, on `CombatBrain`: `@export var uses_gifts: bool = false` (true for the three party scenes) and `@export var feeds_below: int = 30`. On a think, when `uses_gifts` and the unit may act, before the fighting rules and at most one action per think:
  1. **Feed.** If the unit's Blood is below `feeds_below` and a hostile within `aggro_radius` satisfies `can_feed_on`, `order_feed` on the nearest. (This is a brain order.)
  2. **Use a Gift.** For each Gift in slot order that the unit can pay for **without dropping below its `fury_threshold`**:
     - `ALLY` Gift: use it on the living ally (itself included) with the lowest health fraction, if that fraction is below 0.5 and it is in range.
     - `SELF` Gift: use it when at least two living hostiles are within 4 m.
     - `ENEMY` Gift: use it on its current attack target if in range, else on the nearest hostile in range.
  The selected unit's brain is disabled, so the player's character never spends Blood by itself.

- [ ] **Step 1: Write the failing tests** (10 + 7 tests)

```gdscript
# tests/player/test_gift_input.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main
var foe: Unit

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	for enemy: Unit in main.enemies:
		var brain: Node = enemy.get_node("Brain")
		enemy.remove_child(brain)
		brain.free()
	foe = main.enemies[0]
	foe.global_position = main.player.global_position + Vector3(4, 0, 0)
	await wait_physics_frames(2)

func _screen(world: Vector3) -> Vector2:
	return main.rig.camera().unproject_position(world)

func _click(unit: Unit) -> void:
	main.input.click_at(_screen(unit.global_position + Vector3(0, 0.9, 0)))

func test_a_self_gift_fires_on_its_key() -> void:
	main.input.press_gift(0)
	assert_true(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.input.targeting_gift(), -1)

func test_a_targeted_gift_waits_for_a_click_on_a_valid_target() -> void:
	watch_signals(main.input)
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), 1)
	assert_signal_emitted_with_parameters(main.input, "targeting_changed", [1])
	_click(foe)
	assert_true(foe.is_stunned())
	assert_eq(main.input.targeting_gift(), -1)
	assert_eq(main.player.current_order(), Unit.Order.NONE)

func test_a_click_elsewhere_keeps_targeting_and_gives_no_order() -> void:
	main.input.press_gift(1)
	main.input.click_at(_screen(main.player.global_position + Vector3(2, 0, 2)))
	assert_eq(main.input.targeting_gift(), 1)
	assert_eq(main.player.current_order(), Unit.Order.NONE)
	assert_eq(main.player.stats.blood, 60)

func test_the_same_key_or_cancel_closes_targeting() -> void:
	main.input.press_gift(1)
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), -1)
	main.input.press_gift(1)
	main.input.cancel_targeting()
	assert_eq(main.input.targeting_gift(), -1)

func test_a_gift_that_cannot_be_paid_for_does_not_open_targeting() -> void:
	main.player.stats.spend_blood(48)  # 12, above the Fury threshold
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), -1)

func test_the_target_dying_before_the_click_spends_nothing() -> void:
	main.input.press_gift(1)
	var at: Vector2 = _screen(foe.global_position + Vector3(0, 0.9, 0))
	foe.take_hit(999)
	await wait_physics_frames(3)
	main.input.click_at(at)
	assert_eq(main.player.stats.blood, 60)
	assert_eq(main.input.targeting_gift(), 1)

func test_changing_selection_closes_targeting() -> void:
	main.input.press_gift(1)
	main.select(main.party[1])
	assert_eq(main.input.targeting_gift(), -1)

func test_an_ally_gift_can_be_cast_on_a_companion_by_clicking_them() -> void:
	main.select(main.party[1])
	main.party[2].take_hit(60)
	main.input.press_gift(0)
	_click(main.party[2])
	assert_eq(main.party[2].stats.health, 140)
	assert_eq(main.selected, main.party[1])

func test_gifts_can_be_used_while_paused() -> void:
	main.set_paused(true)
	main.input.press_gift(0)
	assert_true(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.player.stats.blood, 40)

func test_restart_and_falling_close_targeting() -> void:
	main.input.press_gift(1)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.input.targeting_gift(), -1)
	main.input.press_gift(0)
	assert_false(main.player.has_effect(&"iron_sinew"))
```

```gdscript
# tests/units/test_companion_behaviour.gd
extends GutTest

var arena: Arena
var alvar: Unit
var zahra: Unit
var gonzalo: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3(-6, 0, 0))
	zahra = arena.spawn(Arena.ZAHRA, Vector3.ZERO, true)
	gonzalo = arena.spawn(Arena.GONZALO, Vector3(3, 0, 0), true)
	await wait_physics_frames(3)

func test_zahra_mends_a_badly_hurt_ally() -> void:
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(80)  # 40 of 120
	await wait_seconds(0.6)
	assert_eq(alvar.stats.health, 80)
	assert_eq(zahra.stats.blood, 40)

func test_zahra_leaves_a_lightly_hurt_ally_alone() -> void:
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(30)
	await wait_seconds(0.6)
	assert_eq(zahra.stats.blood, 60)

func test_zahra_throws_a_lance_at_her_enemy() -> void:
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_seconds(0.6)
	assert_eq(foe.stats.health, 30)

func test_gonzalo_hardens_when_two_enemies_close_in() -> void:
	arena.spawn(Arena.CRUSADER, Vector3(4.5, 0, 0))
	await wait_seconds(0.6)
	assert_false(gonzalo.has_effect(&"stone_hide"))
	arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.5))
	await wait_seconds(0.6)
	assert_true(gonzalo.has_effect(&"stone_hide"))

func test_a_companion_never_spends_itself_into_the_fury() -> void:
	zahra.stats.spend_blood(40)  # 20: a lance would leave 5
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_seconds(1.0)
	assert_eq(zahra.stats.blood, 20)
	assert_false(zahra.is_in_fury())

func test_a_thirsty_companion_feeds_on_a_weakened_enemy() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false  # or her lance would finish his meal
	gonzalo.stats.spend_blood(35)  # 25
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.2))
	foe.take_hit(45)
	await wait_for_signal(gonzalo.fed, 6.0)
	assert_eq(gonzalo.stats.blood, 65)

func test_a_disabled_brain_spends_nothing() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(80)
	await wait_seconds(0.6)
	assert_eq(zahra.stats.blood, 60)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 17 new.
- [ ] **Step 5: Commit** — two commits: `feat: add Gift keys and click targeting`, `feat: let companions use Gifts and feed on their own`

---

### Task 10: The HUD for a party

**Files:**
- Create: `src/ui/party_member_panel.gd`, `scenes/ui/party_member_panel.tscn`, `src/ui/gift_button.gd`, `scenes/ui/gift_button.tscn`, `tests/ui/test_party_hud.gd`
- Modify: `src/ui/hud.gd`, `scenes/ui/hud.tscn`, `src/main.gd`, `tests/ui/test_hud.gd` (rewritten for the new interface, named below), `tests/core/test_main.gd` only if it calls `hud.bind`

**Interfaces:**
- Produces: `class_name PartyMemberPanel extends PanelContainer`
  - `signal pressed(unit: Unit)`; `func bind(unit: Unit) -> void`; `func set_selected(on: bool) -> void`; `func is_selected() -> bool`
  - Children found with `find_child`: `NameLabel` (`Label`), `HealthBar`, `BloodBar` (`ProgressBar`), `StateLabel` (`Label`: `"Fallen"`, `"The Fury"`, `"Feeding"` or empty, in that order of precedence).
  - A left click on the panel emits `pressed` and is consumed, so it gives no order in the world.
- Produces: `class_name GiftButton extends Button`
  - `signal chosen(index: int)`; `func bind(user: GiftUser, index: int) -> void`
  - Text: `"<key> <display name> (<cost>)"`, e.g. `"1 Iron Sinew (20)"`. Disabled when `user.can_use` fails for reasons other than the target (dead, stunned, feeding, Fury, cooldown, Blood). A child `CooldownLabel` shows the seconds left, rounded up, or is empty. `func set_targeting(on: bool) -> void` marks it while its Gift awaits a target (`is_targeting()`).
  - Pressing it emits `chosen(index)`.
- Produces `Hud` (rewritten):
  - `signal member_pressed(unit: Unit)`, `signal gift_chosen(index: int)`
  - `func bind_party(party: Array[Unit]) -> void` — one `PartyMemberPanel` per member, in order, top left.
  - `func show_selected(unit: Unit) -> void` — highlights that panel and rebuilds the Gift bar (bottom centre) from the unit's `Gifts`.
  - `func show_targeting(index: int) -> void`
  - `func panels() -> Array[PartyMemberPanel]`, `func gift_buttons() -> Array[GiftButton]`
  - `func show_fallen()`, `hide_fallen()`, `is_fallen_shown()` as before, text unchanged.
  - `func set_paused(on: bool) -> void` with `PausedLabel` reading `Paused — give your orders`; `func show_cleared() -> void`, `hide_cleared()`, with `ClearedLabel` reading `The vault is quiet`.
  - Labels and containers that are not buttons or panels ignore the mouse.
- `Main` wires it: `bind_party` at room start; `selection_changed` → `show_selected`; `hud.member_pressed` → `select`; `hud.gift_chosen` → `input.press_gift`; `input.targeting_changed` → `show_targeting`; `pause_changed` → `set_paused`; `room_cleared` → `show_cleared`; `start_room()` hides the cleared and fallen labels.
- `tests/ui/test_hud.gd` is replaced by `tests/ui/test_party_hud.gd`; its fallen-prompt test carries over.

- [ ] **Step 1: Write the failing tests** (12 tests)

```gdscript
# tests/ui/test_party_hud.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main
var hud: Hud

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	hud = main.hud

func _panel(index: int) -> PartyMemberPanel:
	return hud.panels()[index]

func test_one_panel_per_member_with_name_health_and_blood() -> void:
	assert_eq(hud.panels().size(), 3)
	assert_eq(_panel(1).find_child("NameLabel").text, "Zahra")
	assert_eq(_panel(1).find_child("HealthBar").max_value, 80.0)
	assert_eq(_panel(1).find_child("HealthBar").value, 80.0)
	assert_eq(_panel(1).find_child("BloodBar").value, 60.0)

func test_bars_follow_the_unit() -> void:
	main.party[2].take_hit(40)
	main.party[2].stats.spend_blood(20)
	assert_eq(_panel(2).find_child("HealthBar").value, 120.0)
	assert_eq(_panel(2).find_child("BloodBar").value, 40.0)

func test_the_selected_panel_is_marked() -> void:
	assert_true(_panel(0).is_selected())
	main.select(main.party[2])
	assert_false(_panel(0).is_selected())
	assert_true(_panel(2).is_selected())

func test_pressing_a_panel_selects_its_member() -> void:
	_panel(1).pressed.emit(main.party[1])
	assert_eq(main.selected, main.party[1])

func test_the_state_label_shows_fallen_then_fury_then_feeding() -> void:
	main.party[1].stats.spend_blood(55)
	await wait_physics_frames(2)
	assert_eq(_panel(1).find_child("StateLabel").text, "The Fury")
	main.party[1].take_hit(999)
	await wait_physics_frames(2)
	assert_eq(_panel(1).find_child("StateLabel").text, "Fallen")
	assert_eq(_panel(0).find_child("StateLabel").text, "")

func test_the_gift_bar_shows_the_selected_members_gifts() -> void:
	assert_eq(hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Iron Sinew (20)", "2 Baleful Eye (15)"])
	main.select(main.party[2])
	assert_eq(hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Stone Hide (20)", "2 Hammerfall (25)"])

func test_a_gift_button_uses_the_gift() -> void:
	hud.gift_buttons()[0].chosen.emit(0)
	assert_true(main.player.has_effect(&"iron_sinew"))

func test_a_gift_on_cooldown_is_disabled_and_counts_down() -> void:
	main.input.press_gift(0)
	await wait_physics_frames(3)
	var button: GiftButton = hud.gift_buttons()[0]
	assert_true(button.disabled)
	assert_eq(button.find_child("CooldownLabel").text, "12")

func test_a_gift_too_dear_is_disabled() -> void:
	main.player.stats.spend_blood(42)  # 18
	await wait_physics_frames(2)
	assert_true(hud.gift_buttons()[0].disabled)   # 20
	assert_false(hud.gift_buttons()[1].disabled)  # 15

func test_targeting_marks_its_button() -> void:
	main.input.press_gift(1)
	assert_true(hud.gift_buttons()[1].is_targeting())
	main.input.cancel_targeting()
	assert_false(hud.gift_buttons()[1].is_targeting())

func test_pause_and_cleared_labels() -> void:
	main.set_paused(true)
	assert_true(hud.find_child("PausedLabel").visible)
	assert_eq(hud.find_child("PausedLabel").text, "Paused — give your orders")
	main.set_paused(false)
	assert_false(hud.find_child("PausedLabel").visible)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(hud.find_child("ClearedLabel").visible)
	assert_eq(hud.find_child("ClearedLabel").text, "The vault is quiet")

func test_the_fallen_prompt_is_unchanged_and_restart_clears_the_labels() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(hud.is_fallen_shown())
	assert_eq(hud.find_child("FallenLabel").text, "You have fallen — press Enter")
	main.start_room()
	assert_false(hud.is_fallen_shown())
	assert_false(hud.find_child("ClearedLabel").visible)
	assert_eq(hud.panels().size(), 3)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.** Plain Godot controls with the default theme; each panel has a small colour swatch matching the unit's body colour.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 12 new, `test_hud.gd` gone.
- [ ] **Step 5: Look at it.** Capture a frame at spawn and one mid-fight (drive a throwaway script, not committed) and read them: three panels top left with readable names and two bars each, the selected one clearly marked, two Gift buttons bottom centre, nothing covering the characters.
- [ ] **Step 6: Commit** — `feat: show the party, their Blood and the selected member's Gifts`

---

### Task 11: The browser build for a party

**Files:**
- Create: `e2e/party.spec.js`
- Modify: `src/core/probe.gd`, `src/main.gd` (registration only), `e2e/smoke.spec.js`, `e2e/resize.spec.js` only if the state shape forces it, `README.md`

**Interfaces:**
- `Main` registers itself with `Probe` in `_enter_tree` through a method `Probe.watch(main: Main) -> void`; `Probe` no longer searches the tree. `Main` calls it only when the autoload exists, and nothing else in `Main` mentions the probe.
- `window.nocturneState` becomes:

```js
{
  party: [{ name, pos: [x, z], health, blood, alive, fury, effects: [ids] }],  // Álvar, Zahra, Gonzalo
  selected: 0,            // index into party
  enemies: 6,             // living
  fallen: false,          // Álvar is down
  paused: false,
  cleared: false,
  targeting: -1,
  fps: 60,
  view: [w, h],
  pos: [x, z], health: 120   // the selected member's, kept so older tests read the same fields
}
```

- With `probe=1&calm=1`, enemy brains are removed at each room start, as before.
- `e2e/smoke.spec.js`: the expected enemy count becomes 6. The test 'approached, the enemies attack and the character can fall and rise again' is deleted: with companions the party may win, so the fall is no longer certain. The full-fight test below covers both endings, and the fall-and-restart loop stays covered by unit tests.
- `README.md`: a "Controls" section — click to move or attack, click a weakened enemy to feed, click a companion or press Tab to select, 1 and 2 for Gifts, Escape to cancel, Space to pause, Q/E and the wheel for the camera, Enter to restart.

- [ ] **Step 1: Write the browser tests**

```js
// e2e/party.spec.js
const { test, expect } = require('@playwright/test');

const state = (page) => page.evaluate(() => { window.nocturneProbe(); return window.nocturneState; });

async function open(page, query) {
  const errors = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', (err) => errors.push(err.message));
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?' + query);
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.waitForTimeout(1000);
  return errors;
}

test('the party of three starts with Álvar selected', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  const s = await state(page);
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar', 'Zahra', 'Gonzalo']);
  expect(s.party.map((m) => m.blood)).toEqual([60, 60, 60]);
  expect(s.selected).toBe(0);
  expect(s.enemies).toBe(6);
  await page.screenshot({ path: 'build/e2e/party.png' });
  expect(errors).toEqual([]);
});

test('Tab selects the next member and the companions follow the leader', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  await page.keyboard.press('Tab');
  await page.waitForFunction(() => { window.nocturneProbe(); return window.nocturneState.selected === 1; });
  const before = await state(page);
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.7, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.party;
    return p[1].pos[0] - from[1] > 1.5 && p[0].pos[0] - from[0] > 0.5;
  }, [before.party[0].pos[0], before.party[1].pos[0]], { timeout: 20000 });
  expect(errors).toEqual([]);
});

test('Space pauses the world and orders wait for it', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  await page.keyboard.press('Space');
  await page.waitForFunction(() => { window.nocturneProbe(); return window.nocturneState.paused; });
  const before = (await state(page)).party[0].pos;
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.7, box.y + box.height * 0.5);
  await page.waitForTimeout(1500);
  const held = (await state(page)).party[0].pos;
  expect(Math.hypot(held[0] - before[0], held[1] - before[1])).toBeLessThan(0.1);
  await page.keyboard.press('Space');
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    return window.nocturneState.party[0].pos[0] - from > 1.0;
  }, before[0], { timeout: 15000 });
  expect(errors).toEqual([]);
});

test('key 1 spends Blood on Iron Sinew', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  await page.keyboard.press('1');
  await page.waitForFunction(() => {
    window.nocturneProbe();
    const m = window.nocturneState.party[0];
    return m.blood === 40 && m.effects.includes('iron_sinew');
  }, null, { timeout: 5000 });
  expect(errors).toEqual([]);
});

test('a full fight runs to an end, and a fall can be restarted', async ({ page }) => {
  test.setTimeout(240000);
  const errors = await open(page, 'probe=1');
  const box = await page.locator('canvas').boundingBox();
  for (let i = 0; i < 40; i++) {
    const s = await state(page);
    if (s.fallen || s.cleared) break;
    await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
    await page.waitForTimeout(3000);
  }
  const end = await state(page);
  expect(end.fallen || end.cleared).toBe(true);
  expect(end.fps).toBeGreaterThanOrEqual(30);
  if (end.fallen) {
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => {
      window.nocturneProbe();
      const s = window.nocturneState;
      return !s.fallen && s.enemies === 6 && s.party.every((m) => m.alive) && s.selected === 0;
    }, null, { timeout: 15000 });
  }
  expect(errors).toEqual([]);
});
```

- [ ] **Step 2: Run to verify failure** — `ops/build-web.sh`, then `npx playwright test --trace off`. Expected: the new file fails on the state shape.
- [ ] **Step 3: Implement the probe changes; update the smoke test's counts and the README.**
- [ ] **Step 4: Build and run** — `ops/build-web.sh`, `npx playwright test --trace off`, `ops/test.sh`. Expected: every browser test passes in Chromium and Firefox; the unit suite passes. Note the size of `build/web` in the commit body.
- [ ] **Step 5: Look at it.** Read `build/e2e/party.png` and describe it in the report: party panels, Gift bar, three party colours and the first enemy group.
- [ ] **Step 6: Commit** — `feat: report the party to browser tests and document the controls`

---

## Amendments made while building

These decisions changed what the tasks above describe. The code follows the amendments.

- **Test totals.** Review fixes added tests; the suite's own report is the count.
- **Task 1.** A frame in which a unit does not steer never counts towards a stall, so a frozen unit keeps its order.
- **Task 2.** Timed effects live in an `Effects` child node; `Unit` keeps the public effect methods. `take_hit` returns, and `was_hit` carries, the health actually removed. The stun test walks to (−4, 0, 0): the original point lay inside the test room's obstacle.
- **Task 3.** `CombatBrain.enabled` is exported, and switching it forgets the brain's chosen target, so an attack still running when a brain comes back on counts as the player's. A follow walk re-aims when the leader moves.
- **Task 4.** The party scenes save their `Brain` disabled; `Main` enables brains for unselected members. A member's fall resets the calm timer, and the fight flow stops while Álvar is down.
- **Task 5.** Selection and pause are refused while Álvar is down. The pause also holds the calm timer.
- **Task 6.** Feeding and the Fury live in `Feeder` and `Fury` child nodes. Only one feed can hold a target. The Fury has no timer of its own: it lasts as long as its effect. `Unit.can_act()` is the single "alive, not stunned, not feeding, not in the Fury" test.
- **Task 7.** `cooldowns_changed` fires only when a cooldown starts, ends or is reset.
- **Task 9.** `GiftUser.is_ready(index)` is the test for "usable apart from its target". Open targeting closes when its Gift stops being ready. The brain's thresholds are exported (`mends_below`, `self_gift_enemies`, `self_gift_radius`). A companion uses an enemy Gift only on its attack target or a hostile inside its aggro radius, never on a meal, and keeps enough Blood for its ally Gift. Brains leave alone any hostile that is being fed on or walked to for a feed. A brain whose idle unit is hit turns on the attacker, at any distance, once the world is running.
- **Task 10.** No HUD control takes keyboard focus, so Space and Enter never press a button.
- **Task 11.** The fall-and-restart browser test is gone: the party may win. Unit tests cover the fall.
- **After the final review.** The Gift first called "Dread Gaze" was renamed "Baleful Eye": the first name belongs to the original game's setting. Each enemy group has one sergeant (90 health, 12 damage) in place of a crusader, so the fight needs the party's Gifts. Enemies that the selected character can feed on carry a mark. Clicking an ally's panel while an ally Gift awaits its target uses the Gift on that ally.

## Carried forward

**Milestone 3 (talk and choose) — first task**
- Move the order system out of `Unit` into an `Orders` child node, with an issuer (player or brain) on each order. Today the Fury-and-feed gate is repeated in four methods of `unit.gd`, the Fury goes round the public order rule through a private chase, and the brain tracks who gave an order with three flags it reconciles on every think. Dialogue adds a walk-up-and-talk order and a second reason to freeze units.

**Milestone 3, further**
- One snapshot and restore per unit (health, Blood, effects, cooldowns) before checkpoints; replace the Enter restart with a checkpoint reload, and add a deterministic browser test of fall and reload.
- Split party, selection and revival out of `Main` before a second room exists.
- Every player-facing string through `tr()`: prompts, state labels, Gift names, unit names.
- After "The vault is quiet" there is nothing to do; room flow decides what comes next.
- A dead companion stays selected if it falls after Álvar. Right click and the wheel are swallowed over HUD panels and buttons.
- Untested: resuming an attack after a stun; the calm timer held while paused; Tab ignored while input is disabled; Gift and cancel key polling; right-click cancel; a real mouse click on a party panel.
- GUT reports orphan nodes at the end of the run.
- Effects can be added to a fallen unit; `was_hit` fires after `died` on a killing blow.

**Milestone 4 (Toledo's look)**
- Units pass through each other and have no avoidance, so attackers on one target stand inside each other.
- HUD panels and Gift buttons reassign their text every frame instead of on change.
- Camera follow runs per frame while units move per physics tick.
- Gift numbers live in both each Gift's script defaults and its resource file; the resource wins.

**Milestone 5 (the night of 1212)**
- Enemies have no leash. A chaser halted in range stops striking if its target shifts less than 0.5 m. A feed ordered while stunned breaks at once. A brain obeys a hostile taunt before a player's order. The ally-Gift rule looks only at the most hurt ally. The stall check would misfire for a heavily slowed unit.
- The selected character does not defend itself when its target dies. Gonzalo walks slower than the others, so the tank arrives last. A companion in the Fury can end the round if Álvar is nearest; companions do not defend themselves against a friend. Fallen companions rise beside whatever felled them.
- Balance after real play: sergeant numbers, starting Blood, feed threshold.
