# Milestone 1: First Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One character walks and fights in a torch-lit vault room, in a desktop browser, with unit tests and a browser test proving it.

**Architecture:** A Godot 4.7 project in GDScript using the Compatibility renderer. Units are `CharacterBody3D` scenes that carry a `Stats` resource and small child nodes for behaviour (melee attack, enemy brain). Input, camera and HUD are separate nodes that talk to units through `order_*` methods and signals. A JavaScript probe exposes game state to Playwright in the exported web build.

**Tech Stack:** Godot 4.7.2, GDScript, GUT 9.6.1 (unit tests), Playwright (browser tests of the web export), `serve` (static server for tests).

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md`

## Where this sits

The spec's slice is too large for one plan. It is built as six milestones, each leaving something playable. This plan is the first; the others get their own plans when their turn comes.

| # | Milestone | Leaves you with |
|---|---|---|
| **1** | **First room (this plan)** | One fighter, one enemy type, one lit room, in the browser |
| 2 | Party and blood | Three characters, pause-and-order, Blood, feeding, the Fury, six Gifts |
| 3 | Talk and choose | Dialogue add-on, Conscience, checkpoints and saving, the forge-haven as a grey-box hub |
| 4 | Toledo's look | Blender kits (arches, vaults, forge), re-dressed characters, portraits, baked lighting |
| 5 | The night of 1212 | All five beats, boss, lock puzzle, audio, Spanish |
| 6 | Out the door | Performance pass, hosting, public URL (needs the owner's go-ahead) |

Milestone 1 uses placeholder shapes (capsules, boxes). No Blender work, no party, no blood, no dialogue.

## Global Constraints

- Godot **4.7** (4.7.2 stable and its export templates are installed), GDScript only, rendering method `gl_compatibility`.
- Export preset `Web`: `variant/thread_support=false`, `variant/extensions_support=false`.
- Required browsers: Chrome and Firefox on desktop. Safari best effort.
- No name, term, text, sound or image from *Vampire: The Masquerade – Redemption* or the World of Darkness. Use the spec's vocabulary table (the Turning, Gifts, Conscience, the Long Sleep, the Veil, the Fury).
- Third-party assets and add-ons are CC0, CC-BY or MIT, and each is listed in `CREDITS.md`.
- Commits: Conventional Commits, subject 72 characters or fewer, one logical change each, authored as `Manuel <emanuel.palacio@gmail.com>`, ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Typed GDScript throughout (`var x: int`, `func f() -> void`). One class per file, `class_name` declared.
- Units of measure: metres and seconds. Ground plane is XZ, Y up.
- All gameplay numbers are `@export` variables with the defaults given here, so later tuning needs no code change.

## Review Focus

1. **A click outside the walkable floor** (on a wall, or the void beyond the room): the character walks to the nearest reachable point; no error, no freeze. Test in Task 3.
2. **An attack order whose target dies or is freed mid-swing:** the attacker stops and idles; no error from a freed reference. Test in Task 4.
3. **Damage larger than remaining health, or zero or negative amounts:** health clamps to 0..max, `died` fires exactly once, negative damage is ignored. Test in Task 2.
4. **The player's character dies:** input is held and a "You have fallen — press Enter" prompt restarts the room; the game never sits in a state with nothing to do. Test in Task 6.
5. **The browser window is resized or loses focus:** the canvas fills the new size and clicks still land on the right ground point afterwards. Test in Task 7.

## File Structure

```
project.godot                 engine config, autoloads, input map
export_presets.cfg            Web preset
.gitignore  README.md  CREDITS.md
addons/gut/                   GUT 9.6.1, unmodified
ops/test.sh                   runs GUT, fails on script errors or missed test files
ops/build-web.sh              exports to build/web/index.html
web/shell.html                HTML shell for the export
package.json  playwright.config.js
src/units/stats.gd            Stats: health and blood numbers, signals
src/units/unit.gd             Unit: moves, takes orders, dies
src/units/melee_attack.gd     MeleeAttack: range, cooldown, damage
src/units/enemy_brain.gd      EnemyBrain: notice, chase, attack
src/player/player_input.gd    PlayerInput: mouse and keys to orders
src/player/camera_rig.gd      CameraRig: follow, rotate, zoom
src/ui/hud.gd                 Hud: health bar, fallen prompt
src/core/probe.gd             Probe: game state for browser tests (autoload)
src/main.gd                   Main: wires the room together, restart
scenes/units/alvar.tscn       player unit (capsule placeholder)
scenes/units/crusader.tscn    enemy unit (capsule placeholder)
scenes/rooms/vault_room.tscn  floor, walls, pillars, navmesh, torches, fog
scenes/ui/hud.tscn
scenes/main.tscn
tests/units/…  tests/player/…  tests/ui/…  tests/fixtures/flat_room.tscn
e2e/smoke.spec.js  e2e/resize.spec.js
```

---

### Task 1: Project skeleton with a passing test

**Files:**
- Create: `project.godot`, `.gitignore`, `README.md`, `CREDITS.md`, `ops/test.sh`, `addons/gut/` (copy), `tests/core/test_project.gd`

**Interfaces:**
- Produces: `ops/test.sh` (no arguments runs every `tests/**/test_*.gd`; arguments replace the selection, e.g. `ops/test.sh -gtest=res://tests/units/test_stats.gd`). Exit code 0 only when all tests pass.

- [ ] **Step 1: Initialise the repository**

In the project root (the directory that already holds `docs/`): `git init -b main`, then `git config user.name "Manuel"` and `git config user.email "emanuel.palacio@gmail.com"`. Verify with `git config user.email`.

- [ ] **Step 2: Add GUT 9.6.1**

Download the 9.6.1 release of `bitwes/Gut` from GitHub and place its `addons/gut` directory at `addons/gut`, unmodified. Add a line for it (name, author Butch Wesley, MIT, URL) to `CREDITS.md`.

- [ ] **Step 3: Write `project.godot`**

`config/name="Nocturne of Ashes"`, `config/features=PackedStringArray("4.7")`, `run/main_scene="res://scenes/main.tscn"`, `renderer/rendering_method="gl_compatibility"` and the same for `.mobile`, editor plugin `res://addons/gut/plugin.cfg` enabled, window 1280×720 with stretch mode `canvas_items` and aspect `expand`.

- [ ] **Step 4: Write `.gitignore`**

`.godot/`, `build/`, `node_modules/`, `test-results/`, `playwright-report/`, `logs/`, `LOCAL.md`, `__pycache__/`, `.superpowers/`.

- [ ] **Step 5: Write `ops/test.sh`**

Bash, `set -uo pipefail`, `cd` to the repository root relative to the script. Run `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` (or the passed arguments in place of the two selection flags), tee to a temp log. Exit non-zero when any of these holds: Godot's exit status is non-zero; the log matches `SCRIPT ERROR|Parse Error|Failed to load script`; the log matches `^Failing Tests +[1-9]`; the log lacks `^Passing Tests +[1-9]`; with no arguments, the `Scripts` count in the log differs from `find tests -name 'test_*.gd' | wc -l`. (Godot exits 0 when a test file fails to parse, which is why the extra checks exist.)

- [ ] **Step 6: Write the first test**

```gdscript
# tests/core/test_project.gd
extends GutTest

func test_project_uses_the_compatibility_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")

func test_project_is_named() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Nocturne of Ashes")
```

- [ ] **Step 7: Run it**

Run: `godot --headless --path . --import` once, then `ops/test.sh`
Expected: `Passing Tests 2`, exit code 0.

- [ ] **Step 8: Write `README.md`**

Title, one paragraph from the spec's Intent, "Run the tests: `ops/test.sh`", and a link to the spec and this plan.

- [ ] **Step 9: Commit**

Two commits: `docs: add the slice design and the first milestone plan` (the `docs/` tree), then `chore: add the Godot project, GUT and the test runner`. Before each, run `git diff --cached | grep -nIE "/Users/|/tmp/|\.lan"` and expect no output.

---

### Task 2: Stats

**Files:**
- Create: `src/units/stats.gd`
- Test: `tests/units/test_stats.gd`

**Interfaces:**
- Produces: `class_name Stats extends Resource`
  - `@export var max_health: int = 100`, `@export var max_blood: int = 100`
  - `var health: int`, `var blood: int` (both start at their maximum; set in `_init` and by `reset()`)
  - `signal health_changed(current: int, maximum: int)`, `signal blood_changed(current: int, maximum: int)`, `signal died`
  - `func reset() -> void`, `func take_damage(amount: int) -> void`, `func heal(amount: int) -> void`, `func spend_blood(amount: int) -> bool`, `func gain_blood(amount: int) -> void`, `func is_dead() -> bool`

Blood is included now so milestone 2 does not change this class's shape; nothing in this milestone spends it.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/units/test_stats.gd
extends GutTest

var stats: Stats

func before_each() -> void:
	stats = Stats.new()

func test_starts_full() -> void:
	assert_eq(stats.health, 100)
	assert_eq(stats.blood, 100)

func test_damage_lowers_health_and_signals() -> void:
	watch_signals(stats)
	stats.take_damage(30)
	assert_eq(stats.health, 70)
	assert_signal_emitted_with_parameters(stats, "health_changed", [70, 100])

func test_overkill_clamps_and_dies_once() -> void:
	watch_signals(stats)
	stats.take_damage(250)
	stats.take_damage(10)
	assert_eq(stats.health, 0)
	assert_true(stats.is_dead())
	assert_signal_emit_count(stats, "died", 1)

func test_zero_and_negative_damage_are_ignored() -> void:
	watch_signals(stats)
	stats.take_damage(0)
	stats.take_damage(-20)
	assert_eq(stats.health, 100)
	assert_signal_not_emitted(stats, "health_changed")

func test_heal_clamps_to_max_and_does_not_raise_the_dead() -> void:
	stats.take_damage(40)
	stats.heal(100)
	assert_eq(stats.health, 100)
	stats.take_damage(100)
	stats.heal(50)
	assert_eq(stats.health, 0)

func test_spend_blood_refuses_what_it_cannot_pay() -> void:
	assert_true(stats.spend_blood(60))
	assert_eq(stats.blood, 40)
	assert_false(stats.spend_blood(41))
	assert_eq(stats.blood, 40)

func test_gain_blood_clamps_to_max() -> void:
	stats.spend_blood(10)
	stats.gain_blood(500)
	assert_eq(stats.blood, 100)

func test_two_stats_do_not_share_numbers() -> void:
	var other := Stats.new()
	stats.take_damage(10)
	assert_eq(other.health, 100)
```

- [ ] **Step 2: Run to verify failure**

Run: `ops/test.sh -gtest=res://tests/units/test_stats.gd`
Expected: non-zero exit, script error naming `Stats`.

- [ ] **Step 3: Implement `Stats` in `src/units/stats.gd`** with the interface above.

- [ ] **Step 4: Run to verify pass**

Run: `ops/test.sh`
Expected: `Passing Tests 10`, exit 0.

- [ ] **Step 5: Commit** — `feat: add health and blood stats`

---

### Task 3: A unit that walks where it is told

**Files:**
- Create: `src/units/unit.gd`, `scenes/units/alvar.tscn`, `tests/fixtures/flat_room.tscn`
- Test: `tests/units/test_unit_movement.gd`

**Interfaces:**
- Consumes: `Stats` (Task 2).
- Produces: `class_name Unit extends CharacterBody3D`
  - `@export var stats: Stats` (duplicated in `_ready` so scene instances never share one), `@export var faction: StringName = &"player"`, `@export var move_speed: float = 4.0`, `@export var display_name: String = ""`
  - `signal died(unit: Unit)`, `signal arrived`
  - `func order_move(target: Vector3) -> void`, `func stop() -> void`, `func is_moving() -> bool`, `func is_alive() -> bool`, `func is_hostile_to(other: Unit) -> bool` (true when factions differ)
  - Joins group `&"units"`. On `stats.died`: stops, disables its collision shape, emits `died(self)`, stays in the tree (the body remains visible, tipped over).
  - Scene shape for every unit scene: root `Unit` (`CharacterBody3D`) → `CollisionShape3D` (capsule, radius 0.35, height 1.8) + `MeshInstance3D` named `Body` + `NavigationAgent3D` named `Agent` (path and target desired distance 0.3).
- Produces: `scenes/units/alvar.tscn` — `faction = &"player"`, `display_name = "Brother Álvar"`, `max_health = 120`, body material off-white.
- Produces: `tests/fixtures/flat_room.tscn` — a `NavigationRegion3D` with a baked 20 m × 20 m flat navmesh centred on the origin, a floor `StaticBody3D`, and one 2 m cube obstacle at (5, 0, 0) cut out of the navmesh. Root has a `Marker3D` named `Spawn` at the origin.

Movement uses `NavigationAgent3D`: `order_move` snaps the target to the navmesh with `NavigationServer3D.map_get_closest_point` before setting it, which is what makes an off-floor click resolve to the nearest reachable point.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/units/test_unit_movement.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

var room: Node3D
var unit: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	unit = ALVAR.instantiate()
	room.add_child(unit)
	unit.global_position = Vector3.ZERO
	await wait_physics_frames(3)  # the navigation map needs a frame to sync

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func test_walks_to_an_ordered_point() -> void:
	unit.order_move(Vector3(0, 0, 6))
	await wait_for_signal(unit.arrived, 4.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(0, 0, 6)), 0.5)
	assert_false(unit.is_moving())

func test_walks_around_an_obstacle() -> void:
	unit.order_move(Vector3(8, 0, 0))
	await wait_for_signal(unit.arrived, 6.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(8, 0, 0)), 0.5)

func test_a_point_off_the_floor_resolves_to_the_nearest_reachable_point() -> void:
	unit.order_move(Vector3(40, 0, 0))
	await wait_for_signal(unit.arrived, 6.0)
	assert_almost_eq(unit.global_position.x, 10.0, 1.0)
	assert_false(unit.is_moving())

func test_stop_halts_the_walk() -> void:
	unit.order_move(Vector3(0, 0, 9))
	await wait_physics_frames(10)
	unit.stop()
	var at := unit.global_position
	await wait_physics_frames(20)
	assert_lt(_flat_distance(unit.global_position, at), 0.05)

func test_a_dead_unit_ignores_orders_and_reports_death_once() -> void:
	watch_signals(unit)
	unit.stats.take_damage(999)
	unit.order_move(Vector3(0, 0, 6))
	await wait_physics_frames(20)
	assert_lt(_flat_distance(unit.global_position, Vector3.ZERO), 0.05)
	assert_false(unit.is_alive())
	assert_signal_emit_count(unit, "died", 1)

func test_instances_do_not_share_stats() -> void:
	var second: Unit = ALVAR.instantiate()
	room.add_child(second)
	unit.stats.take_damage(10)
	assert_eq(second.stats.health, 120)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh -gtest=res://tests/units/test_unit_movement.gd`, expect a script or load error.

- [ ] **Step 3: Build the fixture room and `alvar.tscn`, implement `Unit`.** The fixture's navmesh must be baked and saved in the scene file (bake it from a one-off editor script or `NavigationServer3D.bake_from_source_geometry_data` and save the resource), not baked at test time.

- [ ] **Step 4: Run to verify pass** — `ops/test.sh`, expect `Passing Tests 16`.

- [ ] **Step 5: Commit** — `feat: add a unit that walks by navigation orders`

---

### Task 4: Melee and an enemy that fights back

**Files:**
- Create: `src/units/melee_attack.gd`, `src/units/enemy_brain.gd`, `scenes/units/crusader.tscn`
- Modify: `src/units/unit.gd`, `scenes/units/alvar.tscn` (add the `Melee` child)
- Test: `tests/units/test_melee.gd`, `tests/units/test_enemy_brain.gd`

**Interfaces:**
- Consumes: `Unit`, `Stats`, `tests/fixtures/flat_room.tscn`.
- Produces: `class_name MeleeAttack extends Node` (child of a `Unit`, node name `Melee`)
  - `@export var damage: int = 12`, `@export var attack_range: float = 1.6`, `@export var cooldown: float = 1.0`
  - `signal hit(target: Unit, amount: int)`
  - `func in_range(target: Unit) -> bool` (flat XZ distance ≤ `attack_range`), `func ready_to_swing() -> bool`, `func try_hit(target: Unit) -> bool` (false when out of range, on cooldown, or target dead or freed; otherwise applies damage, starts the cooldown, emits `hit`)
- Produces, added to `Unit`:
  - `func order_attack(target: Unit) -> void`, `func attack_target() -> Unit` (null when none), `signal attack_ended`
  - Behaviour: while it has a valid living target, the unit walks until `Melee.in_range(target)`, then faces the target and calls `try_hit` whenever ready. When the target dies or is freed (`is_instance_valid` false), it clears the target, stops and emits `attack_ended`. `order_move` and `stop` clear the target. Orders on a non-hostile or dead target are ignored.
- Produces: `class_name EnemyBrain extends Node` (child of a `Unit`, node name `Brain`)
  - `@export var aggro_radius: float = 8.0`, `@export var think_interval: float = 0.25`
  - Every `think_interval`, when its unit is alive and has no target, it orders an attack on the nearest living hostile `Unit` in group `&"units"` within `aggro_radius`. No line-of-sight check in this milestone.
- Produces: `scenes/units/crusader.tscn` — `faction = &"crusader"`, `display_name = "Crusader"`, `max_health = 60`, `move_speed = 3.2`, `Melee` with `damage = 8`, `cooldown = 1.4`, a `Brain`, body material dark red.
- `alvar.tscn` gains `Melee` with `damage = 15`, `cooldown = 0.9`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/units/test_melee.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit
var foe: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	foe = CRUSADER.instantiate()
	foe.get_node("Brain").queue_free()  # a passive target for these tests
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3.ZERO
	foe.global_position = Vector3(0, 0, 1.2)
	await wait_physics_frames(3)

func test_a_hit_in_range_does_the_weapon_damage() -> void:
	assert_true(alvar.get_node("Melee").try_hit(foe))
	assert_eq(foe.stats.health, 45)

func test_no_second_hit_inside_the_cooldown() -> void:
	var melee: MeleeAttack = alvar.get_node("Melee")
	melee.try_hit(foe)
	assert_false(melee.try_hit(foe))
	assert_eq(foe.stats.health, 45)

func test_out_of_range_misses() -> void:
	foe.global_position = Vector3(0, 0, 3.0)
	assert_false(alvar.get_node("Melee").try_hit(foe))
	assert_eq(foe.stats.health, 60)

func test_an_attack_order_closes_the_distance_and_kills() -> void:
	foe.global_position = Vector3(0, 0, 7.0)
	alvar.order_attack(foe)
	await wait_for_signal(foe.died, 10.0)
	assert_false(foe.is_alive())
	await wait_physics_frames(5)
	assert_null(alvar.attack_target())
	assert_false(alvar.is_moving())

func test_a_target_freed_mid_fight_ends_the_attack_without_error() -> void:
	watch_signals(alvar)
	alvar.order_attack(foe)
	await wait_physics_frames(5)
	foe.free()
	await wait_physics_frames(10)
	assert_null(alvar.attack_target())
	assert_signal_emitted(alvar, "attack_ended")

func test_orders_against_friends_and_the_dead_are_ignored() -> void:
	var friend: Unit = ALVAR.instantiate()
	room.add_child(friend)
	alvar.order_attack(friend)
	assert_null(alvar.attack_target())
	foe.stats.take_damage(999)
	alvar.order_attack(foe)
	assert_null(alvar.attack_target())

func test_a_move_order_breaks_off_the_attack() -> void:
	alvar.order_attack(foe)
	alvar.order_move(Vector3(-5, 0, 0))
	assert_null(alvar.attack_target())
```

```gdscript
# tests/units/test_enemy_brain.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit
var foe: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	foe = CRUSADER.instantiate()
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3(-8, 0, -8)
	foe.global_position = Vector3(8, 0, 8)
	await wait_physics_frames(3)

func test_ignores_a_player_beyond_the_aggro_radius() -> void:
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_attacks_a_player_who_comes_within_the_radius() -> void:
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_wounds_a_player_who_stands_still() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(4.0)
	assert_lt(alvar.stats.health, 120)

func test_a_dead_enemy_does_nothing() -> void:
	foe.stats.take_damage(999)
	alvar.global_position = Vector3(6, 0, 8)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`, expect load errors for `MeleeAttack` and `crusader.tscn`.
- [ ] **Step 3: Implement `MeleeAttack`, the attack behaviour in `Unit`, `EnemyBrain`, and the two scenes.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`, expect `Passing Tests 27`.
- [ ] **Step 5: Commit** — `feat: add melee combat and an enemy that hunts the player`

---

### Task 5: Camera and mouse control

**Files:**
- Create: `src/player/camera_rig.gd`, `src/player/player_input.gd`
- Modify: `project.godot` (input map)
- Test: `tests/player/test_camera_rig.gd`, `tests/player/test_player_input.gd`

**Interfaces:**
- Consumes: `Unit.order_move`, `Unit.order_attack`, `Unit.is_hostile_to`.
- Produces: `class_name CameraRig extends Node3D` with a child `Camera3D` named `Camera`
  - `@export var pitch_degrees: float = 50.0`, `@export var distance: float = 12.0`, `@export var min_distance: float = 8.0`, `@export var max_distance: float = 18.0`, `@export var zoom_step: float = 1.0`, `@export var rotate_speed: float = 1.6` (radians per second), `@export var follow_sharpness: float = 8.0`
  - `var target: Node3D`
  - `func rotate_by(radians: float) -> void`, `func zoom_by(steps: int) -> void` (positive zooms out; clamped), `func snap_to_target() -> void`, `func camera() -> Camera3D`
  - The rig sits on the target's position (smoothed), yaw on the rig, the camera placed `distance` back along the pitched arm and looking at the rig origin.
- Produces: `class_name PlayerInput extends Node`
  - `var unit: Unit`, `var rig: CameraRig`, `var enabled: bool = true`
  - `func click_at(screen_position: Vector2) -> void` — casts a ray from `rig.camera()` through the point (physics ray, 100 m). A living hostile `Unit` hit → `unit.order_attack`. Anything else with a hit position → `unit.order_move(hit position)`. No physics hit → intersect the ray with the plane Y = 0 and `order_move` there (this is what lets a click beyond the walls resolve to the nearest floor). Does nothing when `enabled` is false or `unit` is dead.
  - `_unhandled_input`: left mouse press → `click_at`; wheel up/down → `rig.zoom_by(-1 / +1)`. `_process`: actions `camera_left` / `camera_right` held → `rig.rotate_by(±rotate_speed * delta)`.
- Input map added to `project.godot`: `camera_left` = Q, `camera_right` = E, `confirm` = Enter and Space.
- Physics layers: layer 1 "world" (floor, walls), layer 2 "units". Unit bodies are on layer 2 and collide with layer 1 only, so units do not shove each other; the click ray tests layers 1 and 2.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/player/test_camera_rig.gd
extends GutTest

var rig: CameraRig
var target: Node3D

func before_each() -> void:
	target = add_child_autofree(Node3D.new())
	rig = CameraRig.new()
	rig.add_child(Camera3D.new())
	rig.get_child(0).name = "Camera"
	add_child_autofree(rig)
	rig.target = target
	rig.snap_to_target()

func test_camera_sits_at_the_set_distance_and_pitch() -> void:
	var offset := rig.camera().global_position - rig.global_position
	assert_almost_eq(offset.length(), 12.0, 0.01)
	assert_almost_eq(rad_to_deg(asin(offset.y / offset.length())), 50.0, 0.1)

func test_zoom_is_clamped() -> void:
	rig.zoom_by(50)
	assert_almost_eq(rig.distance, 18.0, 0.001)
	rig.zoom_by(-50)
	assert_almost_eq(rig.distance, 8.0, 0.001)

func test_rotation_keeps_the_distance() -> void:
	rig.rotate_by(PI / 2)
	var offset := rig.camera().global_position - rig.global_position
	assert_almost_eq(offset.length(), 12.0, 0.01)
	assert_almost_eq(rig.rotation.y, PI / 2, 0.001)

func test_snap_follows_the_target() -> void:
	target.global_position = Vector3(7, 0, -3)
	rig.snap_to_target()
	assert_almost_eq(rig.global_position, Vector3(7, 0, -3), Vector3.ONE * 0.001)
```

```gdscript
# tests/player/test_player_input.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit
var foe: Unit
var rig: CameraRig
var input: PlayerInput

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	foe = CRUSADER.instantiate()
	foe.get_node("Brain").queue_free()
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3.ZERO
	foe.global_position = Vector3(0, 0, -4)
	rig = CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	input = PlayerInput.new()
	room.add_child(input)
	input.unit = alvar
	input.rig = rig
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return rig.camera().unproject_position(world)

func test_a_click_on_the_floor_sends_the_unit_there() -> void:
	input.click_at(_screen(Vector3(3, 0, 2)))
	await wait_for_signal(alvar.arrived, 4.0)
	assert_almost_eq(alvar.global_position.x, 3.0, 0.5)
	assert_almost_eq(alvar.global_position.z, 2.0, 0.5)

func test_a_click_on_an_enemy_orders_an_attack() -> void:
	input.click_at(_screen(foe.global_position + Vector3(0, 0.9, 0)))
	assert_eq(alvar.attack_target(), foe)

func test_a_click_on_the_sky_still_moves_along_the_ground() -> void:
	input.click_at(Vector2(640, 2))
	assert_true(alvar.is_moving())

func test_disabled_input_gives_no_orders() -> void:
	input.enabled = false
	input.click_at(_screen(Vector3(3, 0, 2)))
	assert_false(alvar.is_moving())

func test_a_dead_unit_takes_no_clicks() -> void:
	alvar.stats.take_damage(999)
	input.click_at(_screen(Vector3(3, 0, 2)))
	assert_false(alvar.is_moving())
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`, expect load errors.
- [ ] **Step 3: Implement `CameraRig`, `PlayerInput`, the input map and the physics layers** (set the layers in both unit scenes and the fixture room).
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`, expect `Passing Tests 36`.
- [ ] **Step 5: Commit** — `feat: add the follow camera and click-to-order control`

---

### Task 6: The vault room, the HUD and falling

**Files:**
- Create: `scenes/rooms/vault_room.tscn`, `src/ui/hud.gd`, `scenes/ui/hud.tscn`, `src/main.gd`, `scenes/main.tscn`
- Test: `tests/ui/test_hud.gd`, `tests/core/test_main.gd`

**Interfaces:**
- Consumes: everything above.
- Produces: `scenes/rooms/vault_room.tscn` — a 24 m × 16 m stone-coloured floor, 4 m walls on all sides, six 1 m square pillars in two rows, a baked `NavigationRegion3D` (agent radius 0.4) saved in the scene, `Marker3D` nodes `PlayerSpawn` (west end) and `EnemySpawn1`…`EnemySpawn3` (east half). Lighting: no directional light; four `OmniLight3D` torches on pillars (warm orange, energy 2.0, range 9 m, shadows on for two of them only), a `WorldEnvironment` with a near-black ambient colour, depth fog on (dark blue-grey, density 0.03) and filmic tonemapping. Each torch flickers through an `AnimationPlayer` looping its energy between 1.7 and 2.3, with no script and no particles. (Particles and baked lightmaps are milestone 4.)
- Produces: `class_name Hud extends CanvasLayer`
  - `func bind(unit: Unit) -> void` — shows `unit.display_name` and a health bar that follows `stats.health_changed`
  - `func show_fallen() -> void`, `func hide_fallen() -> void`, `func is_fallen_shown() -> bool` — a centred label with the exact text `You have fallen — press Enter`
  - Node names tests rely on: `HealthBar` (`ProgressBar`), `NameLabel` (`Label`), `FallenLabel` (`Label`), all reachable with `find_child`.
- Produces: `class_name Main extends Node3D`
  - `var player: Unit`, `var enemies: Array[Unit]`, `var input: PlayerInput`, `var rig: CameraRig`, `var hud: Hud`
  - `func start_room() -> void` — frees any existing units, spawns Álvar at `PlayerSpawn` and one crusader at each `EnemySpawn*`, binds camera, input and HUD, enables input, hides the fallen prompt.
  - `func enemies_alive() -> int`
  - On `player.died`: `input.enabled = false`, `hud.show_fallen()`. While fallen, the `confirm` action calls `start_room()`.
  - `_ready` calls `start_room()`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/ui/test_hud.gd
extends GutTest

const HUD := preload("res://scenes/ui/hud.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

var hud: Hud
var unit: Unit

func before_each() -> void:
	hud = add_child_autofree(HUD.instantiate())
	unit = add_child_autofree(ALVAR.instantiate())
	hud.bind(unit)

func test_shows_the_name_and_full_health() -> void:
	assert_eq(hud.find_child("NameLabel").text, "Brother Álvar")
	var bar: ProgressBar = hud.find_child("HealthBar")
	assert_eq(bar.max_value, 120.0)
	assert_eq(bar.value, 120.0)

func test_the_bar_follows_damage() -> void:
	unit.stats.take_damage(20)
	assert_eq(hud.find_child("HealthBar").value, 100.0)

func test_the_fallen_prompt_is_hidden_until_asked() -> void:
	assert_false(hud.is_fallen_shown())
	hud.show_fallen()
	assert_true(hud.is_fallen_shown())
	assert_eq(hud.find_child("FallenLabel").text, "You have fallen — press Enter")
	hud.hide_fallen()
	assert_false(hud.is_fallen_shown())
```

```gdscript
# tests/core/test_main.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)

func test_the_room_starts_with_one_player_and_three_enemies() -> void:
	assert_true(main.player.is_alive())
	assert_eq(main.enemies_alive(), 3)
	assert_true(main.input.enabled)

func test_falling_holds_input_and_shows_the_prompt() -> void:
	main.player.stats.take_damage(999)
	await wait_physics_frames(2)
	assert_false(main.input.enabled)
	assert_true(main.hud.is_fallen_shown())

func test_confirm_after_falling_restarts_the_room() -> void:
	main.player.stats.take_damage(999)
	await wait_physics_frames(2)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.player.stats.health, 120)
	assert_eq(main.enemies_alive(), 3)
	assert_false(main.hud.is_fallen_shown())
	assert_true(main.input.enabled)

func test_confirm_while_alive_does_not_restart() -> void:
	main.player.stats.take_damage(20)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	assert_eq(main.player.stats.health, 100)

func test_every_spawn_point_is_on_the_navmesh() -> void:
	var map := main.get_world_3d().navigation_map
	for marker_name in ["PlayerSpawn", "EnemySpawn1", "EnemySpawn2", "EnemySpawn3"]:
		var at: Vector3 = main.find_child(marker_name).global_position
		assert_lt(at.distance_to(NavigationServer3D.map_get_closest_point(map, at)), 0.3, marker_name)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`, expect load errors.
- [ ] **Step 3: Build the room, the HUD scene and `Main`.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`, expect `Passing Tests 44`.
- [ ] **Step 5: Look at it.** Run `godot --path . --write-movie build/shots/room.png --quit-after 60 --fixed-fps 30` and open the last frame. Expected: floor, pillars and torch pools of light are readable, the far end falls into fog, both unit colours are distinguishable. Adjust light energy and fog density (not the structure) until it is.
- [ ] **Step 6: Commit** — `feat: add the vault room, the health bar and restart after falling`

---

### Task 7: The browser build and its tests

**Files:**
- Create: `export_presets.cfg`, `web/shell.html`, `ops/build-web.sh`, `src/core/probe.gd`, `package.json`, `playwright.config.js`, `e2e/smoke.spec.js`, `e2e/resize.spec.js`
- Modify: `project.godot` (autoload `Probe`), `README.md`

**Interfaces:**
- Consumes: `Main.player`, `Main.enemies_alive()`.
- Produces: `export_presets.cfg` with one preset `Web`: `export_path="build/web/index.html"`, `exclude_filter="addons/gut/*, tests/*, tools/*, node_modules/*, e2e/*, docs/*"`, `variant/thread_support=false`, `variant/extensions_support=false`, `vram_texture_compression/for_desktop=true`, `html/custom_html_shell="res://web/shell.html"`, `html/canvas_resize_policy=2`, `html/focus_canvas_on_start=true`.
- Produces: `web/shell.html` — Godot's default web shell with the title "Nocturne of Ashes", a black page background and a plain "Loading…" progress bar. It must suppress the browser context menu on the canvas.
- Produces: `ops/build-web.sh` — `mkdir -p build/web`, `touch build/.gdignore`, `godot --headless --path . --export-release "Web" build/web/index.html`.
- Produces: autoload `Probe` (`src/core/probe.gd`, `extends Node`). Active only on the web and only when the page URL has `probe=1`. Using `JavaScriptBridge`, it sets `window.nocturneStarted = true` once the main scene is ready and installs `window.nocturneProbe`, a callback that writes
  `window.nocturneState = { pos: [x, z], health: int, enemies: int, fallen: bool, fps: int, view: [width, height] }`
  from the current `Main`. With `probe=1` and `calm=1` the enemies' `Brain` nodes are removed at room start, so a test can move without being attacked.
- Produces: `package.json` (private, script `"test:e2e": "playwright test"`, dev dependencies `@playwright/test` and `serve`), `playwright.config.js` (test directory `e2e`, web server `npx serve -l 8124 --no-clipboard build/web`, base URL `http://127.0.0.1:8124`, projects `chromium` and `firefox`).

- [ ] **Step 1: Write the browser tests**

```js
// e2e/smoke.spec.js
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

test('the room loads without errors and shows the player and three enemies', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  const s = await state(page);
  expect(s.health).toBe(120);
  expect(s.enemies).toBe(3);
  expect(s.fallen).toBe(false);
  await page.screenshot({ path: 'build/e2e/room.png' });
  expect(errors).toEqual([]);
});

test('a click on the floor walks the character there', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&calm=1');
  const start = (await state(page)).pos;
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.pos;
    return Math.hypot(p[0] - from[0], p[1] - from[1]) > 1.5;
  }, start, { timeout: 15000 });
  expect(errors).toEqual([]);
});

test('left alone, the enemies come and the character can fall and rise again', async ({ page }) => {
  test.setTimeout(180000);
  const errors = await open(page, 'probe=1');
  await page.waitForFunction(() => { window.nocturneProbe(); return window.nocturneState.fallen; }, null, { timeout: 120000 });
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => { window.nocturneProbe(); const s = window.nocturneState; return !s.fallen && s.health === 120 && s.enemies === 3; }, null, { timeout: 15000 });
  expect(errors).toEqual([]);
});

test('the room holds 30 frames a second', async ({ page }) => {
  test.setTimeout(90000);
  await open(page, 'probe=1&calm=1');
  await page.waitForTimeout(3000);
  expect((await state(page)).fps).toBeGreaterThanOrEqual(30);
});
```

```js
// e2e/resize.spec.js
const { test, expect } = require('@playwright/test');

const state = (page) => page.evaluate(() => { window.nocturneProbe(); return window.nocturneState; });

test('after a resize and a lost focus the canvas fills the window and clicks still land', async ({ page }) => {
  test.setTimeout(90000);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?probe=1&calm=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.setViewportSize({ width: 900, height: 600 });
  await page.evaluate(() => { window.dispatchEvent(new Event('blur')); window.dispatchEvent(new Event('focus')); });
  await page.waitForTimeout(1000);
  const box = await page.locator('canvas').boundingBox();
  expect(Math.round(box.width)).toBe(900);
  expect(Math.round(box.height)).toBe(600);
  expect((await state(page)).view).toEqual([900, 600]);
  const start = (await state(page)).pos;
  await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.pos;
    return p[0] - from[0] > 1.0;  // the click was east of the character, so it must walk east
  }, start, { timeout: 15000 });
});
```

The last assertion assumes the camera's starting yaw puts world +X to the right of the screen; set `CameraRig`'s initial yaw in `main.tscn` so that holds, and keep `PlayerSpawn` at the west end.

- [ ] **Step 2: Run to verify failure** — `npm install`, then `npx playwright test`. Expected: the web server fails to start because `build/web` does not exist.
- [ ] **Step 3: Write the export preset, shell, build script and `Probe`; register the autoload.**
- [ ] **Step 4: Build** — `ops/build-web.sh`. Expected: `build/web/index.html`, `index.wasm` and `index.pck` exist; note the total size of `build/web` in the commit body (the spec's ceiling is about 80 MB).
- [ ] **Step 5: Run the browser tests** — `npx playwright test --trace off`. Expected: 5 tests × 2 browsers pass. If the frame-rate test fails only in headless Firefox, record the measured figure and report it rather than lowering the threshold.
- [ ] **Step 6: Run the unit tests again** — `ops/test.sh`, expect `Passing Tests 44` (the `Probe` autoload must be inert outside the web).
- [ ] **Step 7: Look at it** — open `build/e2e/room.png`. Expected: the same readable torch-lit room as in Task 6, Step 5. Differences between the desktop and browser renders are the point of this milestone: list any in the task report.
- [ ] **Step 8: Update `README.md`** — add "Build for the browser: `ops/build-web.sh`" and "Browser tests: `npx playwright test`".
- [ ] **Step 9: Commit** — `feat: add the web export with browser tests`
