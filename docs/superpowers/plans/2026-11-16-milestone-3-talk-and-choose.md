# Milestone 3: Talk and Choose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new game opens in the forge-haven: Álvar wakes, talks to five characters, makes two choices that move his Conscience, gains his Gifts and his two companions, and takes the stair down to the vault fight. Progress is saved in the browser and a fall reloads the last checkpoint.

**Architecture:** The order system moves out of `Unit` into an `Orders` child with an issuer on every order. A plain `GameState` object holds everything that outlives a room (Conscience, flags, who has joined, known Gifts, where the party is) and a `SaveStore` writes it as JSON. `Main` becomes a shell that loads `Room` scenes and spawns the party from the state; `scenes/main.tscn` stays the vault skirmish the existing tests use, and a new `scenes/game.tscn` is the story game. Things in a room that are clicked but are not combatants (`Interactable`: characters to talk to, doors) are reached with an interact order. Conversations are written in Dialogue Manager files and run through a thin `DialogueRunner` and a `DialogueBox`.

**Tech Stack:** Godot 4.7.2, GDScript, GUT 9.6.1, Playwright, Dialogue Manager (Nathan Hoad, MIT) for conversations, gettext `.po` files for Spanish.

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md`

**Builds on:** `docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md`, including its "Amendments" and "Carried forward" sections.

## Global Constraints

- Godot **4.7**, GDScript only, rendering method `gl_compatibility`. Web export with threads and extensions off.
- No name, term, text, sound or image from *Vampire: The Masquerade – Redemption* or the World of Darkness. The game's own terms: the Turning, Gifts, Conscience, the Long Sleep, the Veil, the Fury, the Blood-Forged. Each term appears in code as one translatable string in one place, so a later rename is one edit.
- Third-party assets and add-ons are CC0, CC-BY or MIT, each listed in `CREDITS.md`. Add-ons are committed unmodified under `addons/`.
- Commits: Conventional Commits, subject 72 characters or fewer, one logical change each, authored as `Manuel <emanuel.palacio@gmail.com>`, ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Typed GDScript throughout, tabs, one class per file with `class_name` (the `Probe` autoload is the one exception).
- Metres and seconds. Ground plane is XZ, Y up. Distances are measured flat on XZ.
- All gameplay numbers are `@export` variables or named constants with the defaults given here.
- Physics layers: 1 "world", 2 "units", 3 "walls", 4 "interact" (new in Task 6).
- Every string a player can read goes through translation (Task 2): English is the source text, Spanish is in `assets/i18n/es.po`. Tests run with the locale forced to English.
- Test code given in a task is used verbatim. Tests from earlier work stay unchanged unless the task names the change. A test that cannot pass as written is reported, not edited.
- Test output is clean: the only warnings allowed are those a test asserts.
- Pausing never uses `SceneTree.paused`.
- Placeholder look only: capsules, boxes, plain panels. No new art, sound or particles.
- `scenes/main.tscn` keeps working as the vault skirmish: every existing unit test that instantiates it passes unchanged through the whole milestone.
- Every task ends with `ops/test.sh` passing in full.

## Review Focus

1. **A save that cannot be used** (missing, empty, not JSON, wrong shape, an older or newer version number): the game offers only "New game", starts cleanly, and writes a good save at the first checkpoint. No crash, at most one warning. Tests in Task 3 and Task 5.
2. **A conversation at a bad moment:** talking is refused while a fight is on; a unit in the Fury ignores the talk order; a reload or restart while a conversation is open closes it and leaves the world unpaused; clicking the world while the box is open does nothing. Tests in Tasks 6 and 7.
3. **Half-applied choices:** everything a conversation changes (Conscience, flags, joins, Gifts, Blood) is saved once, when the conversation ends. A page reload in the middle of a conversation returns to the checkpoint before it, with none of its effects. Tests in Task 7 and Task 10.
4. **Changing room in any state** (paused, targeting open, a companion fallen or selected, a member feeding): the party arrives unpaused, with targeting closed, the fallen risen at 30 % health, Álvar selected, health and Blood carried over. Tests in Task 4 and Task 9.
5. **Language:** with the locale set to Spanish every on-screen string of the HUD, title and prompts is Spanish, including controls rebuilt after the switch; an unknown locale falls back to English. Tests in Task 2.

## File Structure

```
src/units/orders.gd             Orders: the unit's current order, its issuer, the per-frame decision
src/units/unit.gd               (shrinks) body, hits, death, public methods that delegate
src/units/combat_brain.gd       (modify) reads the issuer; its three ownership flags go
src/core/game_state.gd          GameState: Conscience, flags, joins, Gifts, room, party numbers
src/core/save_store.gd          SaveStore: one JSON save in user://
src/core/story_hooks.gd         StoryHooks: what conversations may call
src/core/language.gd            Language: picks the locale
src/rooms/room.gd               Room: a room's enemies, entries and cleared state
src/rooms/interactable.gd       Interactable: a clickable non-combatant
src/rooms/npc.gd                Npc: an Interactable that starts a conversation
src/rooms/door.gd               Door: an Interactable that leads to another room
src/party/party.gd              Party: members, selection, brains, revival
src/dialogue/dialogue_runner.gd DialogueRunner: adapter over the Dialogue Manager add-on
src/ui/dialogue_box.gd          DialogueBox: speaker, text, numbered choices
src/ui/title_screen.gd          TitleScreen: Continue / New game
src/main.gd                     (modify) shell: rooms, checkpoints, holds; keeps its public facade
scenes/game.tscn                the story game (project main scene); inherits main.tscn
scenes/rooms/forge_haven.tscn   the hub
scenes/rooms/vault_room.tscn    (modify) Room script, entries, doors
scenes/rooms/npc.tscn  door.tscn
scenes/ui/dialogue_box.tscn  title_screen.tscn
dialogue/haven.dialogue         the hub's conversations
assets/i18n/es.po               Spanish
addons/dialogue_manager/        the add-on, unmodified
tests/support/story.gd          Story: boots the story game for tests
tests/fixtures/test_talk.dialogue
tests/…                         one file per task, named in each task
e2e/story.spec.js
```

---

### Task 1: Orders with an issuer

A refactor plus one new fact (who gave the order). The existing suite is the safety net.

**Files:**
- Create: `src/units/orders.gd`, `tests/units/test_order_issuer.gd`
- Modify: `src/units/unit.gd`, `src/units/combat_brain.gd`, `scenes/units/unit_base.tscn`

**Interfaces:**
- Produces, on `Unit`: `enum Issuer { NONE, PLAYER, BRAIN, SYSTEM }` and
  - `func order_move(target: Vector3, issuer: Issuer = Issuer.PLAYER) -> void`
  - `func order_attack(target: Unit, issuer: Issuer = Issuer.PLAYER) -> void`
  - `func order_feed(target: Unit, issuer: Issuer = Issuer.PLAYER) -> void`
  - `func order_issuer() -> Issuer` — `NONE` when the order is `Order.NONE`; `SYSTEM` for what the Fury makes the unit do.
  - Every other public method, signal and export of `Unit` keeps its name and behaviour.
- Produces: `class_name Orders extends Node` (child of a `Unit`, node name `Orders`, placed before `Brain`), which now holds what `unit.gd` held for orders: the current order and its targets, the per-frame choice between walking, striking, approaching a feed and raging, the chase, and the reactions to the mover, the feeder and the Fury. It has one gate for "may this issuer give an order now" (alive; in the Fury only `SYSTEM`) and one place that breaks off the current activity when a new order replaces it. `Unit` calls into it; nothing outside `Unit` talks to `Orders`.
- Changes `CombatBrain`: every order it gives carries `Unit.Issuer.BRAIN`, and "is this order mine" is `order_issuer() == BRAIN`. Its fields `_chosen_target`, `_following` and `_feeding` and their reconciling at the top of each think are removed. A brain's order stays a brain's order when the brain is switched off and on; a player's order stays the player's. The `enabled` setter still stops a walk the brain ordered.
- After this task `src/units/unit.gd` is under 260 lines.

- [ ] **Step 1: Run the suite and note the count** — `ops/test.sh`. Expected: all pass.

- [ ] **Step 2: Write the new tests** (8 tests)

```gdscript
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
```

- [ ] **Step 3: Run to verify failure** — `ops/test.sh -gtest=res://tests/units/test_order_issuer.gd`. Expected: errors for `Unit.Issuer`, `Orders`.
- [ ] **Step 4: Move the order system into `Orders`, add the issuer, simplify the brain.**
- [ ] **Step 5: Run the full suite** — `ops/test.sh`. Expected: every earlier test passes unchanged, plus 8.
- [ ] **Step 6: Commit** — two commits: `refactor: move a unit's orders into an Orders node`, `refactor: tag every order with who gave it`.

---

### Task 2: Every string through translation

**Files:**
- Create: `src/core/language.gd`, `assets/i18n/es.po`, `tests/core/test_language.gd`
- Modify: `project.godot`, `ops/test.sh`, `playwright.config.js`, `src/ui/hud.gd`, `src/ui/party_member_panel.gd`, `src/ui/gift_button.gd`, `scenes/ui/*.tscn` as needed, `src/main.gd`

**Interfaces:**
- English text is the message id. Controls with fixed text rely on Godot's automatic translation of `text`; text built in code uses `tr()` on each part (`tr("%d %s (%d)")` is not used: the Gift button's text is `"%d %s (%d)" % [key, tr(gift.display_name), cost]`).
- `project.godot`: `internationalization/locale/translations` lists `res://assets/i18n/es.po`, fallback `en`.
- Produces: `class_name Language extends RefCounted`
  - `const SUPPORTED: Array[String] = ["en", "es"]`
  - `static func pick(requested: String, system: String) -> String` — `requested` if its language part (before `_` or `-`, lower-cased) is supported, else `system`'s language part if supported, else `"en"`.
  - `static func apply(locale: String) -> void` — `TranslationServer.set_locale`.
  - `static func requested_from_page() -> String` — on the web, the `lang` query parameter, else `""`.
- `Main._enter_tree` calls `Language.apply(Language.pick(Language.requested_from_page(), OS.get_locale()))`, unless the engine was started with `--language` (then it leaves the locale alone).
- `Hud` rebuilds its party panels and Gift bar and re-reads its labels on `NOTIFICATION_TRANSLATION_CHANGED`.
- `ops/test.sh` passes `--language en` to Godot. `playwright.config.js` sets `locale: 'en-US'` for both projects.
- `assets/i18n/es.po` contains at least:

| English | Spanish |
|---|---|
| You have fallen — press Enter | Has caído — pulsa Intro |
| Paused — give your orders | En pausa — da tus órdenes |
| The vault is quiet | La cripta está en silencio |
| Fallen | Caído |
| The Fury | La Furia |
| Feeding | Alimentándose |
| Brother Álvar | Hermano Álvar |
| Crusader | Cruzado |
| Sergeant | Sargento |
| Iron Sinew | Tendón de Hierro |
| Baleful Eye | Ojo Funesto |
| Mend Flesh | Sanar la Carne |
| Blood Lance | Lanza de Sangre |
| Stone Hide | Piel de Piedra |
| Hammerfall | Martillazo |

  "Zahra" and "Gonzalo" are names and need no entry.

- [ ] **Step 1: Write the failing tests** (7 tests)

```gdscript
# tests/core/test_language.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

func after_each() -> void:
	TranslationServer.set_locale("en")

func test_pick_prefers_the_request_then_the_system_then_english() -> void:
	assert_eq(Language.pick("es", "en_US"), "es")
	assert_eq(Language.pick("", "es_ES"), "es")
	assert_eq(Language.pick("ES-mx", "en"), "es")
	assert_eq(Language.pick("sv", "sv_SE"), "en")
	assert_eq(Language.pick("xx", "es_AR"), "es")
	assert_eq(Language.pick("", ""), "en")

func test_english_is_the_source() -> void:
	assert_eq(tr("The vault is quiet"), "The vault is quiet")

func test_spanish_translates_the_prompts() -> void:
	Language.apply("es")
	assert_eq(tr("You have fallen — press Enter"), "Has caído — pulsa Intro")
	assert_eq(tr("Paused — give your orders"), "En pausa — da tus órdenes")
	assert_eq(tr("The vault is quiet"), "La cripta está en silencio")

func test_every_gift_and_unit_name_has_spanish() -> void:
	Language.apply("es")
	for english: String in ["Iron Sinew", "Baleful Eye", "Mend Flesh", "Blood Lance", "Stone Hide", "Hammerfall", "Brother Álvar", "Crusader", "Sergeant", "Fallen", "The Fury", "Feeding"]:
		assert_ne(tr(english), english, english)

func test_the_hud_follows_a_language_change() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons()[0].text, "1 Tendón de Hierro (20)")
	assert_eq(main.hud.panels()[0].find_child("NameLabel").text, "Hermano Álvar")
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.hud.find_child("FallenLabel").text, "Has caído — pulsa Intro")
	assert_eq(main.hud.panels()[0].find_child("StateLabel").text, "Caído")

func test_controls_built_after_the_switch_are_spanish_too() -> void:
	Language.apply("es")
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	main.select(main.party[2])
	assert_eq(main.hud.gift_buttons()[1].text, "2 Martillazo (25)")

func test_an_unknown_locale_reads_as_english() -> void:
	Language.apply(Language.pick("sv", "sv_SE"))
	assert_eq(tr("The Fury"), "The Fury")
```

Note for the fallen-prompt test: the label's text is fixed in the scene and translated automatically; `find_child("FallenLabel").text` returns the source text in Godot for auto-translated controls. If so, the HUD sets that label's text from `tr()` in code so the test reads the shown text. The same applies to `StateLabel`, `PausedLabel` and `ClearedLabel`.

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.** Existing tests that compare English strings keep passing because the test run is forced to English.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 7 new.
- [ ] **Step 5: Commit** — `feat: translate every on-screen string, with Spanish`

---

### Task 3: Game state and the save file

Pure logic, no scenes.

**Files:**
- Create: `src/core/game_state.gd`, `src/core/save_store.gd`, `tests/core/test_game_state.gd`, `tests/core/test_save_store.gd`

**Interfaces:**
- Produces: `class_name GameState extends RefCounted`
  - `const VERSION: int = 1`, `const CONSCIENCE_MAX: int = 10`, `const CONSCIENCE_START: int = 7`
  - `const MEMBERS: Array[StringName] = [&"alvar", &"zahra", &"gonzalo"]`
  - `const ALL_GIFTS: Dictionary = { &"alvar": [&"iron_sinew", &"baleful_eye"], &"zahra": [&"mend_flesh", &"blood_lance"], &"gonzalo": [&"stone_hide", &"hammerfall"] }`
  - `signal conscience_changed(value: int)`, `signal flag_changed(key: StringName)`, `signal member_joined(member: StringName)`, `signal gift_learned(member: StringName, gift: StringName)`
  - `var conscience: int`, `var room: StringName`, `var entry: StringName`
  - `func change_conscience(delta: int) -> void` (clamped to 0…`CONSCIENCE_MAX`; emits only on change)
  - `func set_flag(key: StringName, on: bool = true) -> void`, `func has_flag(key: StringName) -> bool`
  - `func join(member: StringName) -> void`, `func has_joined(member: StringName) -> bool`, `func joined() -> Array[StringName]` (in `MEMBERS` order). Unknown members are ignored; joining twice emits once.
  - `func learn(member: StringName, gift: StringName) -> void`, `func knows(member: StringName, gift: StringName) -> bool`, `func known_gifts(member: StringName) -> Array[StringName]` (in `ALL_GIFTS` order). A Gift that is not that member's is ignored.
  - `func set_vitals(member: StringName, health: int, blood: int) -> void`, `func vitals(member: StringName) -> Vector2i` (`Vector2i(-1, -1)` means "full health, starting Blood")
  - `func to_dict() -> Dictionary` (JSON-safe: strings, numbers, booleans, arrays, dictionaries) and `static func from_dict(data: Variant) -> GameState` (null unless `data` is a dictionary whose `version` equals `VERSION` and whose fields have the right types; unknown extra keys are ignored)
  - `static func new_game() -> GameState` — Conscience 7, room `&"haven"`, entry `&"start"`, only Álvar joined, Álvar knows no Gifts, Zahra and Gonzalo know both of theirs.
  - `static func skirmish() -> GameState` — room `&"vault"`, entry `&"start"`, all three joined, every Gift known.
- Produces: `class_name SaveStore extends RefCounted`
  - `var path: String = "user://save.json"`
  - `func save(state: GameState) -> bool`, `func load_state() -> GameState` (null when there is no file; null with one `push_warning` when the file cannot be used), `func has_save() -> bool` (a usable save exists), `func clear() -> void`

- [ ] **Step 1: Write the failing tests** (11 + 8 tests)

```gdscript
# tests/core/test_game_state.gd
extends GutTest

var state: GameState

func before_each() -> void:
	state = GameState.new_game()

func test_a_new_game_starts_in_the_haven_with_alvar_alone() -> void:
	assert_eq(state.conscience, 7)
	assert_eq(state.room, &"haven")
	assert_eq(state.entry, &"start")
	assert_eq(state.joined(), [&"alvar"] as Array[StringName])
	assert_eq(state.known_gifts(&"alvar"), [] as Array[StringName])
	assert_eq(state.known_gifts(&"zahra"), [&"mend_flesh", &"blood_lance"] as Array[StringName])
	assert_eq(state.vitals(&"alvar"), Vector2i(-1, -1))

func test_a_skirmish_has_everyone_and_everything() -> void:
	var s := GameState.skirmish()
	assert_eq(s.room, &"vault")
	assert_eq(s.joined(), [&"alvar", &"zahra", &"gonzalo"] as Array[StringName])
	assert_true(s.knows(&"alvar", &"baleful_eye"))

func test_conscience_is_clamped_and_signals_only_on_change() -> void:
	watch_signals(state)
	state.change_conscience(-2)
	assert_eq(state.conscience, 5)
	state.change_conscience(-99)
	assert_eq(state.conscience, 0)
	state.change_conscience(-1)
	state.change_conscience(99)
	assert_eq(state.conscience, 10)
	assert_signal_emit_count(state, "conscience_changed", 3)

func test_flags() -> void:
	watch_signals(state)
	assert_false(state.has_flag(&"met_malakor"))
	state.set_flag(&"met_malakor")
	assert_true(state.has_flag(&"met_malakor"))
	state.set_flag(&"met_malakor", false)
	assert_false(state.has_flag(&"met_malakor"))
	assert_signal_emit_count(state, "flag_changed", 2)

func test_flag_and_member_names_given_as_plain_strings_work() -> void:
	state.set_flag("order_given")
	state.join("zahra")
	assert_true(state.has_flag(&"order_given"))
	assert_true(state.has_joined(&"zahra"))

func test_joining_is_once_in_order_and_only_for_real_members() -> void:
	watch_signals(state)
	state.join(&"gonzalo")
	state.join(&"gonzalo")
	state.join(&"zahra")
	state.join(&"malakor")
	assert_eq(state.joined(), [&"alvar", &"zahra", &"gonzalo"] as Array[StringName])
	assert_signal_emit_count(state, "member_joined", 2)

func test_learning_gifts() -> void:
	watch_signals(state)
	state.learn(&"alvar", &"baleful_eye")
	state.learn(&"alvar", &"iron_sinew")
	state.learn(&"alvar", &"iron_sinew")
	state.learn(&"alvar", &"hammerfall")
	assert_eq(state.known_gifts(&"alvar"), [&"iron_sinew", &"baleful_eye"] as Array[StringName])
	assert_signal_emit_count(state, "gift_learned", 2)

func test_vitals_are_kept_per_member() -> void:
	state.set_vitals(&"alvar", 55, 20)
	assert_eq(state.vitals(&"alvar"), Vector2i(55, 20))
	assert_eq(state.vitals(&"zahra"), Vector2i(-1, -1))

func test_a_round_trip_through_json_keeps_everything() -> void:
	state.change_conscience(-3)
	state.set_flag(&"captive_done")
	state.join(&"zahra")
	state.learn(&"alvar", &"iron_sinew")
	state.set_vitals(&"alvar", 80, 35)
	state.room = &"vault"
	state.entry = &"from_haven"
	var text: String = JSON.stringify(state.to_dict())
	var back := GameState.from_dict(JSON.parse_string(text))
	assert_not_null(back)
	assert_eq(back.to_dict(), state.to_dict())
	assert_eq(back.conscience, 4)
	assert_eq(back.room, &"vault")
	assert_true(back.has_flag(&"captive_done"))
	assert_eq(back.joined(), [&"alvar", &"zahra"] as Array[StringName])
	assert_eq(back.vitals(&"alvar"), Vector2i(80, 35))

func test_unusable_data_gives_null() -> void:
	assert_null(GameState.from_dict(null))
	assert_null(GameState.from_dict("save"))
	assert_null(GameState.from_dict({}))
	var old: Dictionary = state.to_dict()
	old["version"] = 0
	assert_null(GameState.from_dict(old))
	var newer: Dictionary = state.to_dict()
	newer["version"] = GameState.VERSION + 1
	assert_null(GameState.from_dict(newer))
	var broken: Dictionary = state.to_dict()
	broken["conscience"] = "seven"
	assert_null(GameState.from_dict(broken))

func test_extra_keys_are_ignored_and_values_are_sanitised() -> void:
	var data: Dictionary = state.to_dict()
	data["something_new"] = 42
	data["conscience"] = 99
	var back := GameState.from_dict(data)
	assert_not_null(back)
	assert_eq(back.conscience, 10)
```

```gdscript
# tests/core/test_save_store.gd
extends GutTest

var store: SaveStore

func before_each() -> void:
	store = SaveStore.new()
	store.path = "user://test_save_%d.json" % randi()
	store.clear()

func after_each() -> void:
	store.clear()

func _write(text: String) -> void:
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func test_no_file_means_no_save() -> void:
	assert_false(store.has_save())
	assert_null(store.load_state())

func test_save_then_load() -> void:
	var state := GameState.new_game()
	state.change_conscience(-2)
	state.join(&"zahra")
	assert_true(store.save(state))
	assert_true(store.has_save())
	var back: GameState = store.load_state()
	assert_eq(back.to_dict(), state.to_dict())

func test_saving_again_replaces_the_save() -> void:
	var state := GameState.new_game()
	store.save(state)
	state.set_flag(&"met_malakor")
	store.save(state)
	assert_true(store.load_state().has_flag(&"met_malakor"))

func test_clear_removes_it() -> void:
	store.save(GameState.new_game())
	store.clear()
	assert_false(store.has_save())
	store.clear()  # clearing nothing is fine

func test_an_empty_file_is_unusable() -> void:
	_write("")
	assert_null(store.load_state())
	assert_push_warning("save")
	assert_false(store.has_save())

func test_a_file_that_is_not_json_is_unusable() -> void:
	_write("{ not json")
	assert_null(store.load_state())
	assert_push_warning("save")

func test_json_of_the_wrong_shape_is_unusable() -> void:
	_write("[1, 2, 3]")
	assert_null(store.load_state())
	assert_push_warning("save")

func test_a_save_from_another_version_is_unusable() -> void:
	var data: Dictionary = GameState.new_game().to_dict()
	data["version"] = GameState.VERSION + 1
	_write(JSON.stringify(data))
	assert_null(store.load_state())
	assert_push_warning("save")
```

The warning text must contain the word `save`. `has_save()` itself raises no warning.

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement `GameState` and `SaveStore`.** Parse with `JSON.new().parse()` so a malformed file does not print an engine error.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 19 new.
- [ ] **Step 5: Commit** — two commits: `feat: add the game state that outlives a room`, `feat: save the game state as one JSON file`

---

### Task 4: Rooms, a party node and the story scene

**Files:**
- Create: `src/rooms/room.gd`, `src/party/party.gd`, `scenes/game.tscn`, `scenes/rooms/forge_haven.tscn` (an empty lit box for now), `tests/support/story.gd`, `tests/core/test_rooms.gd`
- Modify: `src/main.gd`, `scenes/main.tscn`, `scenes/rooms/vault_room.tscn`, `scenes/units/alvar.tscn`, `zahra.tscn`, `gonzalo.tscn`, `project.godot` (main scene), `src/core/probe.gd` only if it reads something that moved

**Interfaces:**
- `Unit` gains `@export var member_id: StringName = &""` (`&"alvar"`, `&"zahra"`, `&"gonzalo"` in the party scenes).
- Produces: `class_name Party extends Node` (child `Party` of `Main`): the members, the leader (Álvar), the selected member, `select`, `select_next`, steering of brains, and raising the fallen. It knows nothing of rooms or enemies.
- Produces: `class_name Room extends Node3D` (script on each room scene's root)
  - `@export var room_id: StringName`, `@export var sergeant_spawns: Array[StringName]` (moved here from `Main`)
  - Entries are `Marker3D` children named `Entry_<name>`, each with two `Marker3D` children `Companion1` and `Companion2`. Every room has `Entry_start`. Enemy markers stay `EnemySpawn<N>`.
  - `func entry(name: StringName) -> Marker3D` (falls back to `Entry_start` with a warning when missing), `func enemy_markers() -> Array[Marker3D]`
- The vault room: `room_id = &"vault"`; `PlayerSpawn`, `CompanionSpawn1/2` become `Entry_start` with its two children at the same world positions; a second entry `Entry_from_haven` at the same place for now.
- The haven for now: `room_id = &"haven"`, a 18 m × 12 m floor with walls on layer 3, a baked navmesh, two warm lights, `Entry_start` near the west end and `Entry_from_vault` near the east end, no enemies.
- Changes `Main` (it keeps every public member that tests use: `party`, `player`, `selected`, `enemies`, `input`, `rig`, `hud`, `select`, `select_next`, `start_room`, `set_paused`, `is_paused`, `is_cleared`, `fight_is_on`, `enemies_alive`, `calm_time`, and its signals; `party`, `player` and `selected` read through to `Party`):
  - `enum Boot { SKIRMISH, STORY }`, `@export var boot: Boot = Boot.SKIRMISH`
  - `var state: GameState`, `var store: SaveStore` (null in a skirmish). Both may be set before the node enters the tree; otherwise a skirmish makes `GameState.skirmish()` and a story makes a `SaveStore` on the default path and a new game.
  - `const ROOMS: Dictionary = { &"vault": preload("res://scenes/rooms/vault_room.tscn"), &"haven": preload("res://scenes/rooms/forge_haven.tscn") }`
  - `var room: Room`
  - `var show_title: bool = true` and `var opening_enabled: bool = true`: both do nothing yet (Tasks 5 and 10 give them meaning); they exist now so the test helper below can switch them off.
  - `func enter_room(room_id: StringName, entry: StringName = &"start") -> void` — unpauses, closes targeting, records the vitals of the living party members into `state` (a fallen member is recorded at 30 % health), frees the old room and every unit, instances the new room, spawns the joined members at the entry with the vitals and known Gifts from `state`, spawns the room's enemies unless `state.has_flag(StringName("%s_cleared" % room_id))`, selects Álvar, sets `state.room` and `state.entry`, emits `room_started`. An unknown `room_id` is refused with a warning and changes nothing.
  - `start_room()` in a skirmish does what it does today (a fresh party at full strength in the vault). In a story it is `enter_room(state.room, state.entry)` after resetting the party's vitals in `state` to what they were when the room was entered.
  - When the room's last enemy falls, `state.set_flag("<room_id>_cleared")`.
- `scenes/main.tscn` no longer contains the vault room as a child: `Main` instances rooms itself. It stays `boot = SKIRMISH`.
- Produces: `scenes/game.tscn`, inheriting `main.tscn` with `boot = STORY`; it becomes `run/main_scene`.
- Produces: `tests/support/story.gd`

```gdscript
class_name Story
extends RefCounted
## Test helper: boots the story game with a throwaway save file.

const GAME: PackedScene = preload("res://scenes/game.tscn")


## Adds the story game to `test`, starting from `state` (a new game when null), with no title screen.
## The opening conversation of a new game plays only when `opening` is true.
static func boot(test: GutTest, state: GameState = null, opening: bool = false) -> Main:
	var main: Main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_story_%d.json" % randi()
	main.store.clear()
	main.state = state if state != null else GameState.new_game()
	main.show_title = false
	main.opening_enabled = opening
	test.add_child_autofree(main)
	return main


static func finish(main: Main) -> void:
	if is_instance_valid(main) and main.store != null:
		main.store.clear()
```

- [ ] **Step 1: Write the failing tests** (11 tests)

```gdscript
# tests/core/test_rooms.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func test_a_new_story_starts_in_the_haven_with_alvar_alone() -> void:
	await _boot()
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.party.size(), 1)
	assert_eq(main.player.member_id, &"alvar")
	assert_eq(main.selected, main.player)
	assert_eq(main.enemies.size(), 0)
	assert_eq((main.player.get_node("Gifts") as GiftUser).count(), 0)

func test_the_skirmish_scene_is_unchanged() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.size(), 3)
	assert_eq(main.enemies_alive(), 6)
	assert_null(main.store)

func test_entering_a_room_spawns_the_joined_members_with_their_known_gifts() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	state.learn(&"alvar", &"iron_sinew")
	await _boot(state)
	main.enter_room(&"vault", &"from_haven")
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"zahra"])
	assert_eq((main.player.get_node("Gifts") as GiftUser).count(), 1)
	assert_eq(main.enemies_alive(), 6)
	assert_eq(main.state.room, &"vault")
	assert_eq(main.state.entry, &"from_haven")
	assert_eq(main.hud.panels().size(), 2)

func test_health_and_blood_travel_between_rooms() -> void:
	var state := GameState.new_game()
	state.join(&"gonzalo")
	await _boot(state)
	main.player.take_hit(50)
	main.player.stats.spend_blood(20)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_eq(main.player.stats.health, 70)
	assert_eq(main.player.stats.blood, 40)
	assert_eq(main.party[1].stats.health, 160)

func test_a_fallen_companion_arrives_risen_at_thirty_percent() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	await _boot(state)
	main.party[1].take_hit(999)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_true(main.party[1].is_alive())
	assert_eq(main.party[1].stats.health, 24)

func test_arrival_is_unpaused_with_alvar_selected_and_no_targeting() -> void:
	var state := GameState.skirmish()
	state.room = &"haven"
	await _boot(state)
	main.select(main.party[1])
	main.input.press_gift(0)
	main.set_paused(true)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_false(main.is_paused())
	assert_eq(main.selected, main.player)
	assert_eq(main.input.targeting_gift(), -1)
	assert_true(main.input.enabled)

func test_a_cleared_room_stays_cleared() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(main.state.has_flag(&"vault_cleared"))
	main.enter_room(&"haven")
	await wait_physics_frames(3)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_eq(main.enemies.size(), 0)
	assert_true(main.is_cleared())

func test_an_unknown_room_is_refused() -> void:
	await _boot()
	main.enter_room(&"nowhere")
	assert_push_warning("nowhere")
	assert_eq(main.room.room_id, &"haven")

func test_a_missing_entry_falls_back_to_start() -> void:
	await _boot()
	main.enter_room(&"vault", &"no_such_entry")
	await wait_physics_frames(3)
	assert_push_warning("no_such_entry")
	assert_eq(main.room.room_id, &"vault")
	assert_true(main.player.is_alive())

func test_every_entry_and_spawn_of_every_room_is_on_its_navmesh() -> void:
	await _boot()
	for room_id: StringName in Main.ROOMS:
		main.enter_room(room_id)
		await wait_physics_frames(3)
		var map := main.get_world_3d().navigation_map
		var markers: Array[Node] = main.room.find_children("Entry_*", "Marker3D", false)
		markers.append_array(main.room.find_children("Companion?", "Marker3D", true))
		markers.append_array(main.room.enemy_markers())
		assert_gt(markers.size(), 2, room_id)
		for marker: Node3D in markers:
			var at: Vector3 = marker.global_position
			assert_lt(at.distance_to(NavigationServer3D.map_get_closest_point(map, at)), 0.3, "%s/%s" % [room_id, marker.name])

func test_restart_in_a_story_returns_to_how_the_room_was_entered() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.player.stats.spend_blood(20)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	main.start_room()
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.player.stats.blood, 40)
	assert_eq(main.enemies_alive(), 6)
```

`tests/core/test_main.gd::test_every_spawn_point_is_on_the_navmesh` names the old markers: update only its marker names (`Entry_start`, `Companion1`, `Companion2`, `EnemySpawn1`…`6`). Any other existing test that looks up `PlayerSpawn`, `CompanionSpawn1/2` or a `VaultRoom` child of `Main` may change only those lookups; say which in the report.

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.** Do the split in this order, running the suite between: `Room` on the vault and `Main` instancing it; `Party` out of `Main`; `GameState` driving spawns; the haven box and `game.tscn`.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 11 new.
- [ ] **Step 5: Commit** — three commits: `refactor: let Main load rooms instead of holding the vault`, `refactor: move the party and its selection into a Party node`, `feat: add the story scene, the haven shell and travel between rooms`

---

### Task 5: Checkpoints, reload after a fall, and the title

**Files:**
- Create: `src/ui/title_screen.gd`, `scenes/ui/title_screen.tscn`, `tests/core/test_checkpoints.gd`, `tests/ui/test_title_screen.gd`
- Modify: `src/main.gd`, `scenes/game.tscn`, `assets/i18n/es.po`

**Interfaces:**
- Produces, on `Main` (story boot only; a skirmish never touches a store):
  - `func checkpoint() -> void` — records the party's vitals into `state` and saves it. Called at the end of `enter_room` and wherever later tasks say. `signal checkpoint_saved`.
  - `func reload_checkpoint() -> void` — loads the store's state (a new game if none is usable) and enters its room at its entry. In a story, `confirm` after Álvar's fall calls this in place of `start_room()`.
  - `func new_game() -> void` — clears the store, replaces `state` with `GameState.new_game()`, enters the haven.
  - `show_title` (declared in Task 4; `Story.boot` sets it false before adding the node) now takes effect. With it true, a story boot shows the title first and enters no room until a choice is made; the world is held (units container disabled) and input is off meanwhile.
- Produces: `class_name TitleScreen extends Control`
  - `signal continue_chosen`, `signal new_game_chosen`
  - `func open(can_continue: bool) -> void`, `func close() -> void`, `func is_open() -> bool`
  - Shows the title `Nocturne of Ashes`, a `ContinueButton` (`Continue`, hidden when `can_continue` is false) and a `NewGameButton` (`New game`). No control takes keyboard focus. While open, the `confirm` action chooses Continue when it is offered and New game otherwise.
- `es.po` gains: Continue → Continuar, New game → Nueva partida. The title itself is not translated.

- [ ] **Step 1: Write the failing tests** (9 + 5 tests)

```gdscript
# tests/core/test_checkpoints.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func test_entering_a_room_saves() -> void:
	await _boot()
	assert_true(main.store.has_save())
	assert_eq(main.store.load_state().room, &"haven")

func test_a_skirmish_never_saves() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	main.checkpoint()  # must not error
	assert_null(main.store)

func test_a_checkpoint_keeps_vitals_and_progress() -> void:
	await _boot()
	main.player.take_hit(30)
	main.state.change_conscience(-2)
	main.state.set_flag(&"met_malakor")
	watch_signals(main)
	main.checkpoint()
	assert_signal_emitted(main, "checkpoint_saved")
	var saved: GameState = main.store.load_state()
	assert_eq(saved.vitals(&"alvar").x, 90)
	assert_eq(saved.conscience, 5)
	assert_true(saved.has_flag(&"met_malakor"))

func test_a_fall_reloads_the_last_checkpoint() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.state.change_conscience(-3)  # after the checkpoint: must be undone
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(main.hud.is_fallen_shown())
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.state.conscience, 7)
	assert_eq(main.enemies_alive(), 6)
	assert_false(main.hud.is_fallen_shown())
	assert_eq(main.party.size(), 3)

func test_reload_restores_the_room_the_save_names() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.enter_room(&"haven", &"from_vault")
	await wait_physics_frames(3)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.entry, &"from_vault")

func test_reload_with_an_unusable_save_starts_a_new_game() -> void:
	await _boot()
	var file := FileAccess.open(main.store.path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_push_warning("save")
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.conscience, 7)
	assert_true(main.store.has_save())

func test_new_game_wipes_progress() -> void:
	var state := GameState.skirmish()
	state.change_conscience(-5)
	await _boot(state)
	main.new_game()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.party.size(), 1)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.store.load_state().joined(), [&"alvar"] as Array[StringName])

func test_the_cleared_flag_is_saved_at_once() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(main.store.load_state().has_flag(&"vault_cleared"))

func test_reload_closes_pause_and_targeting() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.input.press_gift(1)
	main.set_paused(true)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_false(main.is_paused())
	assert_eq(main.input.targeting_gift(), -1)
```

```gdscript
# tests/ui/test_title_screen.gd
extends GutTest

const GAME := preload("res://scenes/game.tscn")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot_with_title(saved: GameState) -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_title_%d.json" % randi()
	main.store.clear()
	if saved != null:
		main.store.save(saved)
	add_child_autofree(main)
	await wait_physics_frames(3)

func _title() -> TitleScreen:
	return main.find_child("TitleScreen") as TitleScreen

func test_without_a_save_only_new_game_is_offered() -> void:
	await _boot_with_title(null)
	assert_true(_title().is_open())
	assert_false(_title().find_child("ContinueButton").visible)
	assert_true(_title().find_child("NewGameButton").visible)
	assert_null(main.room)
	assert_false(main.input.enabled)

func test_new_game_enters_the_haven() -> void:
	await _boot_with_title(null)
	_title().new_game_chosen.emit()
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_eq(main.room.room_id, &"haven")
	assert_true(main.input.enabled)

func test_continue_restores_the_save() -> void:
	var saved := GameState.skirmish()
	saved.change_conscience(-4)
	await _boot_with_title(saved)
	assert_true(_title().find_child("ContinueButton").visible)
	_title().continue_chosen.emit()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.state.conscience, 3)
	assert_eq(main.party.size(), 3)

func test_enter_continues_when_it_can_and_starts_anew_when_it_cannot() -> void:
	var saved := GameState.skirmish()
	await _boot_with_title(saved)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")

func test_an_unusable_save_offers_only_new_game() -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_title_%d.json" % randi()
	var file := FileAccess.open(main.store.path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	add_child_autofree(main)
	await wait_physics_frames(3)
	assert_false(_title().find_child("ContinueButton").visible)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 14 new.
- [ ] **Step 5: Commit** — two commits: `feat: checkpoint the story and reload it after a fall`, `feat: add a title with Continue and New game`

---

### Task 6: Things to click that are not combatants

**Files:**
- Create: `src/rooms/interactable.gd`, `tests/rooms/test_interactables.gd`
- Modify: `src/units/unit.gd`, `src/units/orders.gd`, `src/player/picker.gd`, `src/player/player_input.gd`, `src/main.gd`, `project.godot` (layer name), `tests/support/arena.gd` (a helper to add an interactable)

**Interfaces:**
- Layer 4 is named "interact".
- Produces: `class_name Interactable extends StaticBody3D` (collision layer 4 only, mask 0)
  - `@export var label: String = ""` (what it is, translatable), `@export var reach: float = 2.0`
  - `signal used(by: Unit)`
  - `func can_be_used_by(unit: Unit) -> bool` — true by default; subclasses narrow it.
  - `func use(by: Unit) -> void` — emits `used` when `can_be_used_by(by)`; subclasses add what happens.
  - It is not in the `&"units"` group: brains and the Fury never see it.
- `Picker.interactable_at(camera: Camera3D, screen: Vector2) -> Interactable` — first body on layer 4 under the point, or null.
- `Unit`: `Order.INTERACT` and `func order_interact(target: Interactable, issuer: Issuer = Issuer.PLAYER) -> void` — the unit walks until within `target.reach` (flat), stops, calls `target.use(self)`, and its order ends. Refused when the gate refuses the issuer, when `target` is null or freed, or when `not target.can_be_used_by(self)`. A target freed on the way ends the order without error. `signal interacted(target: Interactable)`.
- `PlayerInput.click_at`, outside targeting: a unit under the point is handled as before; otherwise an interactable under the point gives `order_interact`; otherwise the ground gives `order_move`. While targeting, interactables are ignored.
- `Main.fight_is_on()` is what later interactables consult; nothing here uses it yet.

- [ ] **Step 1: Write the failing tests** (9 tests)

```gdscript
# tests/rooms/test_interactables.gd
extends GutTest

var arena: Arena
var alvar: Unit
var thing: Interactable

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	thing = arena.add_interactable(Vector3(0, 0, 6))
	await wait_physics_frames(3)

func test_an_interact_order_walks_up_and_uses_it() -> void:
	watch_signals(thing)
	watch_signals(alvar)
	alvar.order_interact(thing)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)
	await wait_for_signal(thing.used, 5.0)
	assert_signal_emitted_with_parameters(thing, "used", [alvar])
	assert_signal_emitted_with_parameters(alvar, "interacted", [thing])
	assert_lt(Arena.flat(alvar.global_position, thing.global_position), 2.2)
	assert_gt(Arena.flat(alvar.global_position, thing.global_position), 1.0)
	await wait_physics_frames(2)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_already_in_reach_it_is_used_at_once() -> void:
	alvar.global_position = Vector3(0, 0, 4.5)
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(3)
	assert_signal_emit_count(thing, "used", 1)

func test_a_new_order_breaks_it_off() -> void:
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_physics_frames(5)
	alvar.order_move(Vector3(-4, 0, 0))
	await wait_seconds(2.5)
	assert_signal_not_emitted(thing, "used")

func test_a_target_freed_on_the_way_ends_the_order() -> void:
	alvar.order_interact(thing)
	await wait_physics_frames(5)
	thing.free()
	await wait_physics_frames(5)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_the_fury_ignores_interact_orders() -> void:
	alvar.stats.spend_blood(55)
	await wait_physics_frames(3)
	alvar.order_interact(thing)
	assert_ne(alvar.current_order(), Unit.Order.INTERACT)

func test_a_stunned_unit_keeps_the_order_and_finishes_it() -> void:
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 0.5
	stun.stuns = true
	alvar.add_effect(stun)
	watch_signals(thing)
	alvar.order_interact(thing)
	await wait_for_signal(thing.used, 6.0)
	assert_signal_emit_count(thing, "used", 1)

func test_brains_and_the_fury_do_not_see_interactables() -> void:
	assert_false(thing.is_in_group(&"units"))

func test_the_picker_finds_it_and_a_click_orders_the_interaction() -> void:
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	arena.room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	var input := PlayerInput.new()
	arena.room.add_child(input)
	input.unit = alvar
	input.rig = rig
	await wait_physics_frames(2)
	var at: Vector2 = cam.unproject_position(thing.global_position + Vector3(0, 0.9, 0))
	assert_eq(Picker.interactable_at(cam, at), thing)
	input.click_at(at)
	assert_eq(alvar.current_order(), Unit.Order.INTERACT)

func test_one_that_refuses_is_not_approached() -> void:
	var picky := arena.add_interactable(Vector3(-6, 0, 0), func(_u: Unit) -> bool: return false)
	alvar.order_interact(picky)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
```

`Arena.add_interactable(at: Vector3, allow: Callable = Callable()) -> Interactable` adds an `Interactable` with a 0.7 m × 1.8 m capsule collider on layer 4 at `at`; when `allow` is valid it decides `can_be_used_by` (use a small inner subclass in `arena.gd`).

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 9 new.
- [ ] **Step 5: Commit** — `feat: add interactables and an order to walk up and use them`

---

### Task 7: Conversations

**Files:**
- Create: `addons/dialogue_manager/` (the add-on), `src/dialogue/dialogue_runner.gd`, `src/core/story_hooks.gd`, `src/ui/dialogue_box.gd`, `scenes/ui/dialogue_box.tscn`, `src/rooms/npc.gd`, `scenes/rooms/npc.tscn`, `tests/fixtures/test_talk.dialogue`, `tests/dialogue/test_dialogue_runner.gd`, `tests/dialogue/test_conversations.gd`
- Modify: `project.godot` (the add-on's plugin and autoload), `CREDITS.md`, `export_presets.cfg` only if the add-on needs files included, `src/main.gd`, `scenes/main.tscn`, `src/ui/hud.gd`, `assets/i18n/es.po`

**Interfaces:**
- **The add-on.** Install Dialogue Manager v4.2.0 (released for Godot 4.7, MIT), unmodified, with its licence, and list it in `CREDITS.md`. Version 4 calls a conversation's entry points "cues" (the `~ name` lines) and writes a response's condition self-closing (`- Text [if condition /]`). Step 1 below proves it works here before anything is built on it.
- Produces: `class_name StoryHooks extends RefCounted` — the only object conversations can call. Built by `Main` with the state and a way to reach Álvar.
  - `func conscience() -> int`, `func change_conscience(delta: int) -> void`
  - `func has_flag(key: String) -> bool`, `func set_flag(key: String) -> void`
  - `func join(member: String) -> void`, `func has_joined(member: String) -> bool`
  - `func learn(member: String, gift: String) -> void`
  - `func give_blood(amount: int) -> void` (to Álvar, capped at his maximum), `func blood() -> int`
- Produces: `class_name DialogueRunner extends Node` — the one place that touches the add-on's API.
  - `signal line_shown(speaker: String, text: String, choices: Array[String])` (`choices` is empty for a plain line; only choices whose condition holds are listed), `signal finished`
  - `func start(resource: Resource, title: String, hooks: StoryHooks) -> void`, `func advance() -> void` (for a plain line), `func choose(index: int) -> void`, `func stop() -> void` (ends without running anything further; emits `finished`), `func is_running() -> bool`
  - `advance()` on a line with choices and `choose()` out of range do nothing.
- Produces: `class_name DialogueBox extends Control` (in the HUD layer, bottom of the screen)
  - `func bind(runner: DialogueRunner) -> void`; visible exactly while the runner runs.
  - Children found with `find_child`: `SpeakerLabel`, `TextLabel` (`RichTextLabel` or `Label`), `Choices` (a container of buttons whose text is `"<n>. <choice>"`).
  - A plain line advances on the `confirm` action or a left click on the box. Choices are taken by clicking one or pressing its number (actions `choice_1`…`choice_4`, keys 1–4). No control takes keyboard focus. A click on the box never reaches the world.
- Produces: `class_name Npc extends Interactable` and `scenes/rooms/npc.tscn` (a capsule like a unit's, with a `Body` mesh whose colour is exported)
  - `@export var dialogue: Resource`, `@export var title: String = "start"`, `@export var shown_if: StringName = &""`, `@export var hidden_if: StringName = &""` (flags; the room hides an `Npc` and disables its collider accordingly, at room start and whenever a flag changes)
  - `signal talk_requested(npc: Npc, by: Unit)` on `use`.
- Changes `Main`:
  - `var dialogue: DialogueRunner` (a child node), `func talk(resource: Resource, title: String) -> void`, `func is_talking() -> bool`.
  - While a conversation runs the world is held (units container disabled, as for the pause, but for its own reason: Space cannot release it), `PlayerInput` is disabled, targeting is closed and the Gift keys do nothing. When it finishes: input returns, and in a story `checkpoint()` is called.
  - `talk` is refused while `fight_is_on()`, while Álvar is down, and while already talking.
  - `Main` connects every `Npc`'s `talk_requested` in the room to `talk(npc.dialogue, npc.title)`.
  - `enter_room`, `reload_checkpoint`, `new_game` and `start_room` stop a running conversation first, without a checkpoint.
  - Gift keys 1 and 2 and the dialogue's choice keys 1–4 are different actions on the same keys; only one set is live at a time.
- `tests/fixtures/test_talk.dialogue` (in the add-on's syntax):

```
~ start
Smith: The forge is cold tonight.
Smith: What will you do with the prisoner?
- Spare him
	do change_conscience(1)
	do set_flag("spared")
	Smith: Mercy. Rare here.
- Drain him
	do change_conscience(-2)
	do give_blood(40)
	Smith: So be it.
- Say the secret word [if has_flag("knows_word") /]
	Smith: You should not know that.
=> END

~ again
if conscience() >= 8
	Smith: You walk lightly, friend.
else
	Smith: I have seen that look before.
=> END
```

- [ ] **Step 1: Prove the add-on works here.** Install it, enable its plugin, run `godot --headless --path . --import` and `ops/test.sh` (no new errors or warnings), then `ops/build-web.sh` and load the build once with Playwright's existing smoke test. If the newest version fails on any of these, try the previous major version. If neither works, stop and report BLOCKED with the errors: do not write a replacement.

- [ ] **Step 2: Write the failing tests** (9 + 12 tests)

```gdscript
# tests/dialogue/test_dialogue_runner.gd
extends GutTest

const TALK := preload("res://tests/fixtures/test_talk.dialogue")

var runner: DialogueRunner
var state: GameState
var hooks: StoryHooks
var lines: Array = []

func before_each() -> void:
	lines = []
	state = GameState.new_game()
	hooks = StoryHooks.new(state, func() -> Unit: return null)
	runner = add_child_autofree(DialogueRunner.new())
	runner.line_shown.connect(func(speaker: String, text: String, choices: Array[String]) -> void:
		lines.append([speaker, text, choices]))

func _last() -> Array:
	return lines[-1]

func test_start_shows_the_first_line() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	assert_true(runner.is_running())
	assert_eq(_last(), ["Smith", "The forge is cold tonight.", []])

func test_advance_reaches_the_choices_and_hides_those_not_allowed() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_eq(_last()[1], "What will you do with the prisoner?")
	assert_eq(_last()[2], ["Spare him", "Drain him"])

func test_a_choice_runs_its_effects_and_its_reply() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(0)
	await wait_physics_frames(2)
	assert_eq(state.conscience, 8)
	assert_true(state.has_flag(&"spared"))
	assert_eq(_last()[1], "Mercy. Rare here.")

func test_the_other_choice_has_its_own_effects() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(1)
	await wait_physics_frames(2)
	assert_eq(state.conscience, 5)
	assert_false(state.has_flag(&"spared"))

func test_a_condition_can_open_a_choice() -> void:
	state.set_flag(&"knows_word")
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_eq(_last()[2].size(), 3)

func test_it_finishes_after_the_last_line() -> void:
	watch_signals(runner)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(0)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_false(runner.is_running())
	assert_signal_emit_count(runner, "finished", 1)

func test_lines_can_depend_on_conscience() -> void:
	runner.start(TALK, "again", hooks)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "I have seen that look before.")
	runner.stop()
	state.change_conscience(2)
	runner.start(TALK, "again", hooks)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "You walk lightly, friend.")

func test_wrong_inputs_do_nothing() -> void:
	runner.advance()
	runner.choose(0)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.choose(0)   # no choices on this line
	await wait_physics_frames(2)
	assert_eq(_last()[1], "The forge is cold tonight.")
	runner.advance()
	await wait_physics_frames(2)
	runner.advance()   # choices are up
	runner.choose(7)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "What will you do with the prisoner?")

func test_stop_ends_without_running_more() -> void:
	watch_signals(runner)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.stop()
	assert_false(runner.is_running())
	assert_signal_emit_count(runner, "finished", 1)
	assert_eq(state.conscience, 7)
```

```gdscript
# tests/dialogue/test_conversations.gd
extends GutTest

const TALK := preload("res://tests/fixtures/test_talk.dialogue")
const NPC := preload("res://scenes/rooms/npc.tscn")

var main: Main
var smith: Npc

func after_each() -> void:
	Story.finish(main)

func before_each() -> void:
	main = Story.boot(self)
	await wait_physics_frames(3)
	smith = NPC.instantiate()
	smith.dialogue = TALK
	smith.label = "Smith"
	main.room.add_child(smith)
	smith.global_position = main.player.global_position + Vector3(3, 0, 0)
	smith.talk_requested.connect(func(npc: Npc, _by: Unit) -> void: main.talk(npc.dialogue, npc.title))
	await wait_physics_frames(2)

func _box() -> DialogueBox:
	return main.find_child("DialogueBox") as DialogueBox

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)

func test_walking_up_to_someone_opens_the_conversation() -> void:
	main.player.order_interact(smith)
	await wait_for_signal(main.dialogue.line_shown, 5.0)
	assert_true(main.is_talking())
	assert_true(_box().visible)
	assert_eq(_box().find_child("SpeakerLabel").text, "Smith")
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_the_world_is_held_and_input_is_off_while_talking() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	assert_false(main.input.enabled)
	var from: Vector3 = main.player.global_position
	main.player.order_move(from + Vector3(-3, 0, 0))
	await wait_seconds(0.5)
	assert_lt(Arena.flat(main.player.global_position, from), 0.05)
	await _tap(&"pause")
	assert_false(main.is_paused())

func test_confirm_advances_and_number_keys_choose() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	var buttons: Array[Node] = _box().find_child("Choices").get_children()
	assert_eq(buttons.map(func(b: Node) -> String: return (b as Button).text), ["1. Spare him", "2. Drain him"])
	await _tap(&"choice_2")
	assert_eq(main.state.conscience, 5)
	assert_string_contains(_box().find_child("TextLabel").text, "So be it.")

func test_confirm_does_not_skip_a_choice() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"confirm")
	assert_string_contains(_box().find_child("TextLabel").text, "What will you do with the prisoner?")
	assert_eq(main.state.conscience, 7)

func test_gift_keys_do_nothing_while_talking() -> void:
	main.state.learn(&"alvar", &"iron_sinew")
	main.enter_room(&"haven")
	await wait_physics_frames(3)
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"gift_1")
	assert_false(main.player.has_effect(&"iron_sinew"))

func test_blood_given_in_a_conversation_reaches_alvar() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_2")
	assert_eq(main.player.stats.blood, 100)

func test_the_end_returns_control_and_saves_once() -> void:
	watch_signals(main)
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_1")
	assert_signal_not_emitted(main, "checkpoint_saved")
	await _tap(&"confirm")
	assert_false(main.is_talking())
	assert_false(_box().visible)
	assert_true(main.input.enabled)
	assert_signal_emit_count(main, "checkpoint_saved", 1)
	assert_true(main.store.load_state().has_flag(&"spared"))

func test_a_reload_mid_conversation_undoes_it() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_2")
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_false(main.is_talking())
	assert_false(_box().visible)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.player.stats.blood, 60)
	assert_true(main.input.enabled)
	assert_false(main.is_paused())

func test_no_talking_after_a_fall() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	main.talk(TALK, "start")
	assert_false(main.is_talking())

func test_no_talking_while_a_fight_is_on() -> void:
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	main.enemies[0].order_attack(main.player)
	await wait_physics_frames(2)
	main.talk(TALK, "start")
	assert_false(main.is_talking())

func test_a_second_talk_while_talking_is_refused() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	main.talk(TALK, "again")
	await wait_physics_frames(2)
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_someone_hidden_by_a_flag_cannot_be_clicked() -> void:
	smith.hidden_if = &"smith_gone"
	main.state.set_flag(&"smith_gone")
	await wait_physics_frames(2)
	assert_false(smith.visible)
	assert_false(smith.can_be_used_by(main.player))
```

`StoryHooks.new(state, alvar_getter)` takes the state and a `Callable` returning Álvar's unit (or null), so it holds no stale unit.

- [ ] **Step 3: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 4: Implement the runner, the hooks, the box, `Npc`, and the changes to `Main`.**
- [ ] **Step 5: Run to verify pass** — `ops/test.sh`. Expected: all pass, 21 new.
- [ ] **Step 6: Look at it.** Capture one frame with the box open on a choice (throwaway driver script) and read it: speaker, text and numbered choices readable at the bottom, party panels still visible, nothing overlapping.
- [ ] **Step 7: Commit** — three commits: `chore: add the Dialogue Manager add-on`, `feat: run conversations through a runner and a dialogue box`, `feat: let the player walk up to characters and talk`

---

### Task 8: Conscience on screen, Gifts learned and companions joining mid-room

**Files:**
- Create: `tests/core/test_story_progress.gd`
- Modify: `src/main.gd`, `src/party/party.gd`, `src/ui/hud.gd`, `scenes/ui/hud.tscn`, `assets/i18n/es.po`

**Interfaces:**
- `Hud`: a `ConscienceLabel` (top right) reading `Conscience 7/10` (`"%s %d/%d" % [tr("Conscience"), value, GameState.CONSCIENCE_MAX]`), following `state.conscience_changed`. It is shown in a story and hidden in a skirmish. `func bind_state(state: GameState) -> void`.
- `Main` reacts to the state while a room is live:
  - `gift_learned(member, gift)` → that member's `Gifts` are rebuilt from `state.known_gifts(member)` (cooldowns of Gifts already known are kept), and the Gift bar refreshes if the member is selected.
  - `member_joined(member)` → the member's unit is spawned beside the `Npc` whose `label` is that member's display name if one is in the room (else at the entry's next free companion marker), with full health and starting Blood, added to the party in `MEMBERS` order, panels rebuilt, brains steered. The selection does not change.
- Joining and learning inside a conversation take effect when they are called (so the HUD changes behind the box); the save happens at the conversation's end as before.
- `es.po` gains: Conscience → Conciencia.

- [ ] **Step 1: Write the failing tests** (8 tests)

```gdscript
# tests/core/test_story_progress.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func before_each() -> void:
	main = Story.boot(self)
	await wait_physics_frames(3)

func _label() -> Label:
	return main.hud.find_child("ConscienceLabel") as Label

func test_conscience_is_shown_and_follows_changes() -> void:
	assert_true(_label().visible)
	assert_eq(_label().text, "Conscience 7/10")
	main.state.change_conscience(-2)
	assert_eq(_label().text, "Conscience 5/10")

func test_it_is_hidden_in_a_skirmish() -> void:
	var skirmish: Main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	assert_false((skirmish.hud.find_child("ConscienceLabel") as Label).visible)

func test_it_follows_the_state_after_a_reload() -> void:
	main.state.change_conscience(-3)
	main.checkpoint()
	main.state.change_conscience(-3)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(_label().text, "Conscience 4/10")
	main.state.change_conscience(1)
	assert_eq(_label().text, "Conscience 5/10")

func test_a_learned_gift_appears_at_once() -> void:
	assert_eq(main.hud.gift_buttons().size(), 0)
	main.state.learn(&"alvar", &"baleful_eye")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Baleful Eye (15)"])
	main.state.learn(&"alvar", &"iron_sinew")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Iron Sinew (20)", "2 Baleful Eye (15)"])

func test_learning_keeps_a_running_cooldown() -> void:
	main.state.learn(&"alvar", &"iron_sinew")
	await wait_physics_frames(2)
	main.input.press_gift(0)
	await wait_physics_frames(2)
	main.state.learn(&"alvar", &"baleful_eye")
	await wait_physics_frames(2)
	var gifts := main.player.get_node("Gifts") as GiftUser
	assert_gt(gifts.cooldown_left(0), 10.0)
	assert_eq(gifts.cooldown_left(1), 0.0)

func test_a_companion_who_joins_appears_and_follows() -> void:
	main.state.join(&"gonzalo")
	await wait_physics_frames(3)
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"gonzalo"])
	assert_eq(main.hud.panels().size(), 2)
	assert_eq(main.selected, main.player)
	var brain := main.party[1].get_node("Brain") as CombatBrain
	assert_true(brain.enabled)
	assert_eq(brain.leader, main.player)
	assert_eq(main.party[1].stats.health, 160)

func test_members_keep_their_order_whoever_joins_first() -> void:
	main.state.join(&"gonzalo")
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"zahra", &"gonzalo"])
	assert_eq(main.hud.panels()[1].find_child("NameLabel").text, "Zahra")

func test_a_joined_companion_is_saved_and_returns_after_reload() -> void:
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	main.checkpoint()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.party.size(), 2)
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 8 new.
- [ ] **Step 5: Commit** — `feat: show Conscience and bring Gifts and companions in as they are won`

---

### Task 9: Doors and the way between the haven and the vault

**Files:**
- Create: `src/rooms/door.gd`, `scenes/rooms/door.tscn`, `tests/rooms/test_doors.gd`
- Modify: `src/main.gd`, `scenes/rooms/vault_room.tscn`, `scenes/rooms/forge_haven.tscn`, `src/ui/hud.gd`, `scenes/ui/hud.tscn`, `assets/i18n/es.po`

**Interfaces:**
- Produces: `class_name Door extends Interactable` and `scenes/rooms/door.tscn` (a dark box 1.4 m wide, 2.4 m tall, standing against a wall)
  - `@export var to_room: StringName`, `@export var to_entry: StringName = &"start"`
  - `@export var needs_flags: Array[StringName] = []` (all must be set), `@export var locked_text: String = ""`
  - `signal travel_requested(door: Door)`, `signal refused(text: String)`
  - `func is_locked(state: GameState) -> bool`
  - `use(by)`: only Álvar's unit may use a door (`by.member_id == &"alvar"`); a companion sent to a door walks there and nothing happens.
- `Main` connects each door in the room: on use, if `fight_is_on()` it shows the notice `Not while they are upon you`; else if locked, the door's `locked_text`; else `enter_room(door.to_room, door.to_entry)`. A door with an empty `to_room` only ever shows its `locked_text`.
- `Hud`: `func show_notice(text: String) -> void` — a line in the middle of the screen (`NoticeLabel`) that goes after 2.5 s or when replaced; `func notice() -> String` (empty when none).
- The haven gets `StairDoor` at its east wall: `to_room = &"vault"`, `to_entry = &"from_haven"`, `needs_flags = [&"order_given"]`, `locked_text = "The stair is barred until Malakor says otherwise"`.
- The vault gets `WestDoor` at its west wall beside `Entry_from_haven`: `to_room = &"haven"`, `to_entry = &"from_vault"`; and `LastLock` at its east wall: `to_room = &""`, `locked_text = "The last lock does not yield. Not yet."`.
- In the skirmish the vault's doors are inert: `Main` connects doors only in a story.
- `es.po` gains: Not while they are upon you → No mientras los tengas encima; The stair is barred until Malakor says otherwise → La escalera está cerrada hasta que Malakor diga otra cosa; The last lock does not yield. Not yet. → El último cerrojo no cede. Aún no.

- [ ] **Step 1: Write the failing tests** (9 tests)

```gdscript
# tests/rooms/test_doors.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func _door(node_name: String) -> Door:
	return main.room.find_child(node_name) as Door

func test_the_stair_is_barred_until_the_order_is_given() -> void:
	await _boot()
	_door("StairDoor").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.hud.notice(), "The stair is barred until Malakor says otherwise")

func test_with_the_order_the_stair_leads_to_the_vault() -> void:
	var state := GameState.new_game()
	state.set_flag(&"order_given")
	await _boot(state)
	main.player.order_interact(_door("StairDoor"))
	await wait_for_signal(main.room_started, 10.0)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.state.entry, &"from_haven")
	assert_eq(main.enemies_alive(), 6)
	assert_eq(main.store.load_state().room, &"vault")

func test_no_leaving_while_a_fight_is_on() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.enemies[0].order_attack(main.player)
	await wait_physics_frames(2)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "Not while they are upon you")

func test_the_way_back_to_the_haven_arrives_at_the_stair() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_lt(Arena.flat(main.player.global_position, _door("StairDoor").global_position), 4.0)

func test_the_last_lock_never_opens() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	_door("LastLock").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "The last lock does not yield. Not yet.")

func test_only_alvar_opens_doors() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	assert_false(_door("WestDoor").can_be_used_by(main.party[1]))
	_door("WestDoor").use(main.party[1])
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")

func test_a_notice_fades() -> void:
	await _boot()
	main.hud.show_notice("The stair is barred until Malakor says otherwise")
	assert_eq(main.hud.notice(), "The stair is barred until Malakor says otherwise")
	await wait_seconds(2.8)
	assert_eq(main.hud.notice(), "")

func test_every_door_stands_within_reach_of_the_navmesh() -> void:
	await _boot()
	for room_id: StringName in Main.ROOMS:
		main.enter_room(room_id)
		await wait_physics_frames(3)
		var map := main.get_world_3d().navigation_map
		for door: Node in main.room.find_children("*", "Door", true, false):
			var at: Vector3 = (door as Door).global_position
			var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, at)
			assert_lt(Arena.flat(at, on_mesh), (door as Door).reach - 0.3, "%s/%s" % [room_id, door.name])

func test_doors_do_nothing_in_the_skirmish() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	(main.room.find_child("WestDoor") as Door).use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "")
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement.** Rebake each room's navmesh if a door's box changes the walkable floor; doors are on layer 4 and are not navmesh obstacles.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 9 new.
- [ ] **Step 5: Commit** — `feat: add doors between the haven and the vault`

---

### Task 10: The forge-haven and its people

Content. The mechanics all exist; this task builds the room and writes its conversations.

**Files:**
- Create: `dialogue/haven.dialogue`, `tests/story/test_haven.gd`
- Modify: `scenes/rooms/forge_haven.tscn`, `src/main.gd` (the opening conversation only), `assets/i18n/es.po` (labels only; conversation text is translated in milestone 5)

**The room.** The 18 m × 12 m box from Task 4 becomes a forge cellar in grey-box: a forge (a box with a strong orange light) against the north wall, an anvil and a rack as boxes, a barred alcove in the south-west corner for the captive, the stair door at the east wall. Dark, lit by the forge and two torches. Everything a character can stand on stays on the navmesh.

**The people** (`Npc` instances; names are the labels; body colours distinct from each other and from the party):

| Node | Label | Where | Shown / hidden by |
|---|---|---|---|
| `Malakor` | Malakor | by the forge | always |
| `Smith` | Íñigo | at the anvil | always |
| `Captive` | The captive | in the alcove | hidden when `captive_dead` |
| `ZahraNpc` | Zahra | east side | hidden when Zahra has joined (flag `zahra_joined`, set with the join) |
| `GonzaloNpc` | Gonzalo | by the rack | hidden when `gonzalo_joined` |

**The conversations** (`dialogue/haven.dialogue`). The implementer writes the lines: plain, short, in period, no modern idiom, 2–6 lines a beat, using only this game's terms. Each beat below fixes what happens; `[state]` lines are the calls the file must make.

- `~ waking` — starts by itself when a new game enters the haven (`Main`: if `opening_enabled`, the room is the haven and `met_malakor` is not set, `talk(haven, "waking")` once the room has started). Malakor tells Álvar he died in the burning quarter and was turned; that he now belongs to the Blood-Forged; that the woman he guarded got away with what she carried. He gives the first Gift. `[learn("alvar", "iron_sinew")]`, `[set_flag("met_malakor")]`.
- `~ malakor` — three states.
  - Before both companions have joined and the captive is dealt with: he sends Álvar to find them and to "see to the prisoner".
  - Once `zahra_joined`, `gonzalo_joined` and `captive_done` are all set, and `order_given` is not: he orders Álvar below to break the old locks, and demands the letter Álvar carried for Elena. **Choice** (the second Conscience choice): *Hand it over* `[change_conscience(-1)]`, `[set_flag("gave_letter")]`; or *Say it burned in the quarter* `[change_conscience(1)]`, `[set_flag("kept_letter")]`. Either way `[set_flag("order_given")]`.
  - After `order_given`: one line sending him down. If `conscience() <= 4`, a line that he approves of what Álvar is becoming; if `conscience() >= 8`, a line of suspicion.
- `~ smith` — Íñigo explains, in his own words, Blood (Gifts spend it), feeding (the weak can be drunk from), the Fury (what happens when it runs dry), and the Veil. No choice. A second visit gives one different line.
- `~ captive` — a wounded crusader. **Choice** (the first Conscience choice), offered until `captive_done`: *Drink a little* `[give_blood(30)]`, `[set_flag("captive_done")]`; *Drain him* `[give_blood(100)]`, `[change_conscience(-2)]`, `[set_flag("captive_dead")]`, `[set_flag("captive_done")]`; *Leave him be* `[change_conscience(1)]`, `[set_flag("captive_done")]`. After `captive_done` and alive: one line that depends on which was chosen.
- `~ zahra` — the physician. Wary of Malakor, curious about Álvar. She joins and teaches the second Gift. `[join("zahra")]`, `[set_flag("zahra_joined")]`, `[learn("alvar", "baleful_eye")]`.
- `~ gonzalo` — the old smith-soldier. Loyal to the bloodline, blunt. He joins. `[join("gonzalo")]`, `[set_flag("gonzalo_joined")]`.

Elena is named only as "the translator" or by name once by Álvar; Malakor does not know her name.

- [ ] **Step 1: Write the failing tests** (14 tests)

```gdscript
# tests/story/test_haven.gd
extends GutTest

const HAVEN := preload("res://dialogue/haven.dialogue")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state, true)
	await wait_physics_frames(3)

## Plays the open conversation to its end, taking `choice` (0-based) at every choice.
func _play_through(choice: int = 0) -> void:
	var guard: int = 0
	while main.is_talking() and guard < 60:
		guard += 1
		var buttons: Array[Node] = main.find_child("DialogueBox").find_child("Choices").get_children()
		if buttons.size() > 0:
			main.dialogue.choose(mini(choice, buttons.size() - 1))
		else:
			main.dialogue.advance()
		await wait_physics_frames(2)
	assert_lt(guard, 60, "the conversation did not end")

func _talk(title: String, choice: int = 0) -> void:
	main.talk(HAVEN, title)
	await wait_physics_frames(2)
	await _play_through(choice)

func _after_waking() -> GameState:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	state.learn(&"alvar", &"iron_sinew")
	return state

func test_a_new_game_opens_on_the_waking() -> void:
	await _boot()
	await wait_physics_frames(3)
	assert_true(main.is_talking())
	assert_eq(main.find_child("DialogueBox").find_child("SpeakerLabel").text, "Malakor")
	await _play_through()
	assert_true(main.state.has_flag(&"met_malakor"))
	assert_true(main.state.knows(&"alvar", &"iron_sinew"))
	assert_eq(main.hud.gift_buttons().size(), 1)

func test_the_waking_plays_only_once() -> void:
	await _boot(_after_waking())
	await wait_physics_frames(3)
	assert_false(main.is_talking())

func test_five_people_stand_in_the_haven() -> void:
	await _boot(_after_waking())
	var names: Array = main.room.find_children("*", "Npc", true, false).map(func(n: Node) -> String: return (n as Npc).label)
	names.sort()
	assert_eq(names, ["Gonzalo", "Malakor", "The captive", "Zahra", "Íñigo"])

func test_zahra_joins_and_teaches() -> void:
	await _boot(_after_waking())
	await _talk("zahra")
	assert_eq(main.party.size(), 2)
	assert_true(main.state.knows(&"alvar", &"baleful_eye"))
	assert_false((main.room.find_child("ZahraNpc") as Npc).visible)

func test_gonzalo_joins() -> void:
	await _boot(_after_waking())
	await _talk("gonzalo")
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"gonzalo"])

func _meet_the_captive(choice: int) -> void:
	await _boot(_after_waking())
	main.player.stats.spend_blood(30)  # 30
	await _talk("captive", choice)
	assert_true(main.state.has_flag(&"captive_done"))

func test_drinking_a_little_from_the_captive() -> void:
	await _meet_the_captive(0)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.player.stats.blood, 60)
	assert_false(main.state.has_flag(&"captive_dead"))
	assert_true((main.room.find_child("Captive") as Npc).visible)

func test_draining_the_captive() -> void:
	await _meet_the_captive(1)
	assert_eq(main.state.conscience, 5)
	assert_eq(main.player.stats.blood, 100)
	assert_true(main.state.has_flag(&"captive_dead"))
	assert_false((main.room.find_child("Captive") as Npc).visible)

func test_leaving_the_captive_be() -> void:
	await _meet_the_captive(2)
	assert_eq(main.state.conscience, 8)
	assert_eq(main.player.stats.blood, 30)

func test_the_captive_decides_only_once() -> void:
	await _boot(_after_waking())
	await _talk("captive", 2)
	await _talk("captive", 1)
	assert_eq(main.state.conscience, 8)
	assert_false(main.state.has_flag(&"captive_dead"))

func test_malakor_gives_no_order_before_the_rest_is_done() -> void:
	await _boot(_after_waking())
	await _talk("malakor")
	assert_false(main.state.has_flag(&"order_given"))
	assert_eq(main.state.conscience, 7)

func _receive_the_order(choice: int) -> void:
	var state := _after_waking()
	state.join(&"zahra")
	state.join(&"gonzalo")
	for flag: StringName in [&"zahra_joined", &"gonzalo_joined", &"captive_done"]:
		state.set_flag(flag)
	await _boot(state)
	await _talk("malakor", choice)
	assert_true(main.state.has_flag(&"order_given"))
	assert_false((main.room.find_child("StairDoor") as Door).is_locked(main.state))

func test_handing_over_the_letter() -> void:
	await _receive_the_order(0)
	assert_eq(main.state.conscience, 6)
	assert_true(main.state.has_flag(&"gave_letter"))
	assert_false(main.state.has_flag(&"kept_letter"))

func test_keeping_the_letter() -> void:
	await _receive_the_order(1)
	assert_eq(main.state.conscience, 8)
	assert_true(main.state.has_flag(&"kept_letter"))
	assert_false(main.state.has_flag(&"gave_letter"))

func test_the_smith_talks_without_changing_anything() -> void:
	await _boot(_after_waking())
	var before: Dictionary = main.state.to_dict()
	await _talk("smith")
	await _talk("smith")
	assert_eq(main.state.to_dict(), before)

func test_the_whole_haven_can_be_played_to_the_vault() -> void:
	await _boot()
	await wait_physics_frames(3)
	await _play_through()
	for title: String in ["smith", "captive", "zahra", "gonzalo", "malakor"]:
		await _talk(title, 0)
	assert_true(main.state.has_flag(&"order_given"))
	(main.room.find_child("StairDoor") as Door).use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.size(), 3)
	assert_eq(main.hud.gift_buttons().size(), 2)
	assert_eq(main.state.conscience, 6)
```

A check that is not a test but must hold: `git grep -inE "embrace|kindred|masquerade|discipline|humanity|torpor|frenzy|clan |sire|childe|ghoul|prince" dialogue/` returns nothing.

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Build the room, place the people, write the conversations, add the opening.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass, 14 new.
- [ ] **Step 5: Look at it.** Capture a frame of the haven at the start (box open on Malakor's first line) and one with all five people in view; read both and describe them in the report.
- [ ] **Step 6: Paste every line of `dialogue/haven.dialogue` into the report**, so the text can be read and judged without opening the file.
- [ ] **Step 7: Commit** — two commits: `feat: build the forge-haven and place its people`, `feat: write the haven's conversations and its two choices`

---

### Task 11: The browser build for a story

**Files:**
- Create: `e2e/story.spec.js`
- Modify: `src/core/probe.gd`, `src/main.gd` (query parameters only), `e2e/smoke.spec.js`, `e2e/party.spec.js`, `e2e/resize.spec.js`, `README.md`

**Interfaces:**
- The web build now opens on the story (`scenes/game.tscn`). Page parameters, read once at start, only on the web:
  - `skirmish=1` — boot the vault skirmish instead (no title, no save). The three existing spec files add it to every query.
  - `probe=1` — as before, and in a story it skips the title: Continue if a usable save exists, else New game.
  - `fresh=1` — clear the save before anything else.
  - `frail=1` — with `probe=1` only: Álvar's health is set to 1 whenever a room with enemies starts.
  - `at=vault` — with `probe=1` and `fresh=1` only: start as if the haven were finished (everyone joined, both of Álvar's Gifts, `captive_done`, `order_given`), entering the vault from the haven.
  - `title=1` — show the title even with `probe=1`.
  - `lang=es` — Task 2.
- `window.nocturneState` gains: `room`, `conscience`, `flags` (array of set flag names, sorted), `talking`, `speaker`, `line`, `choices` (array of strings), `notice`, `title` (the title screen is open), `saved` (a usable save exists). Existing fields stay.
- `README.md`: the Controls section gains talking (click a character; Enter or click to go on; 1–4 to choose), doors, and that progress is saved in the browser; a short "Story so far" paragraph naming the haven and the vault.

- [ ] **Step 1: Write the browser tests**

```js
// e2e/story.spec.js
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

const until = (page, fn, arg, timeout = 15000) => page.waitForFunction(fn, arg, { timeout });

// Presses Enter through plain lines and `key` at each choice until the conversation ends.
async function talkThrough(page, key) {
  for (let i = 0; i < 60; i++) {
    const s = await state(page);
    if (!s.talking) return;
    await page.keyboard.press(s.choices.length > 0 ? key : 'Enter');
    await page.waitForTimeout(250);
  }
  throw new Error('the conversation did not end');
}

test('a new game wakes in the haven and Malakor speaks first', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  const s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.speaker).toBe('Malakor');
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar']);
  expect(s.conscience).toBe(7);
  await page.screenshot({ path: 'build/e2e/waking.png' });
  await talkThrough(page, '1');
  const after = await state(page);
  expect(after.flags).toContain('met_malakor');
  expect(after.saved).toBe(true);
  expect(errors).toEqual([]);
});

test('progress survives a page reload', async ({ page }) => {
  test.setTimeout(120000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await talkThrough(page, '1');
  await page.goto('/?probe=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  const s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.talking).toBe(false);
  expect(s.flags).toContain('met_malakor');
  expect(errors).toEqual([]);
});

test('a reload in the middle of a conversation undoes it', async ({ page }) => {
  test.setTimeout(120000);
  await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  await page.goto('/?probe=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  const s = await state(page);
  expect(s.flags).not.toContain('met_malakor');
  expect(s.speaker).toBe('Malakor');
});

test('the title leads into a new game', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&fresh=1&title=1');
  const s = await state(page);
  expect(s.title).toBe(true);
  expect(s.room).toBe('');
  await page.screenshot({ path: 'build/e2e/title.png' });
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); const t = window.nocturneState; return !t.title && t.room === 'haven'; });
  expect(errors).toEqual([]);
});

test('clicking someone starts a conversation and a choice moves Conscience', async ({ page }) => {
  test.setTimeout(120000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await talkThrough(page, '1');
  const at = (await state(page)).people['The captive'];
  const box = await page.locator('canvas').boundingBox();
  expect(at[0]).toBeGreaterThan(0);
  expect(at[0]).toBeLessThan(box.width);
  expect(at[1]).toBeGreaterThan(0);
  expect(at[1]).toBeLessThan(box.height);
  await page.mouse.click(box.x + at[0], box.y + at[1]);
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; }, null, 20000);
  expect((await state(page)).speaker).toBe('The captive');
  await talkThrough(page, '3');
  const after = await state(page);
  expect(after.conscience).toBe(8);
  expect(after.flags).toContain('captive_done');
  expect(errors).toEqual([]);
});

test('a fall in the vault reloads the checkpoint', async ({ page }) => {
  test.setTimeout(180000);
  const errors = await open(page, 'probe=1&fresh=1&at=vault&frail=1');
  const start = await state(page);
  expect(start.room).toBe('vault');
  expect(start.party.length).toBe(3);
  const box = await page.locator('canvas').boundingBox();
  for (let i = 0; i < 25; i++) {
    if ((await state(page)).fallen) break;
    await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
    await page.waitForTimeout(2000);
  }
  expect((await state(page)).fallen).toBe(true);
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); const s = window.nocturneState; return !s.fallen && s.room === 'vault' && s.enemies === 6; });
  expect((await state(page)).party.length).toBe(3);
  expect(errors).toEqual([]);
});

test('Spanish on request', async ({ page }) => {
  test.setTimeout(90000);
  await open(page, 'probe=1&skirmish=1&lang=es');
  const s = await state(page);
  expect(s.party[0].name).toBe('Hermano Álvar');
});
```

  The probe also reports `people`: a map from each visible `Npc`'s and `Door`'s name (an `Npc`'s `label`, a `Door`'s node name) to the screen point `[x, y]`, in CSS pixels relative to the canvas, of a point 0.9 m up its body. `party[].name` is the translated display name. `room` is `''` while the title is open. The captive's alcove must be on screen from where a new game starts (Task 10 places it in the south-west corner, near `Entry_start`).

- [ ] **Step 2: Run to verify failure** — `ops/build-web.sh`, then `npx playwright test --trace off`.
- [ ] **Step 3: Implement the parameters and the probe fields; add `skirmish=1` to the three older spec files; update the README.**
- [ ] **Step 4: Build and run** — `ops/build-web.sh`, `npx playwright test --trace off`, `ops/test.sh`. Expected: every browser test passes in Chromium and Firefox; the unit suite passes. Note the size of `build/web` in the commit body.
- [ ] **Step 5: Look at it.** Read `build/e2e/waking.png` and `build/e2e/title.png` and describe them in the report.
- [ ] **Step 6: Commit** — `feat: play the story in the browser, with saves that survive a reload`

---

### Task 12: Loose ends carried from earlier milestones

**Files:**
- Create: `tests/core/test_loose_ends.gd`
- Modify: as each item needs

Each item is one small change with its test.

1. **A fallen companion never stays selected.** If the selected companion is down and cannot be handed to Álvar (he is down too), the selection moves to the first living member, or stays on Álvar when nobody lives. Test.
2. **Effects are not added to the fallen.** `Unit.add_effect` on a dead unit does nothing. Test.
3. **`was_hit` before `died` on a killing blow.** A listener of `was_hit` sees the hit before the unit's death is announced. Test with both signals recorded in order.
4. **An order on a map that never becomes ready warns once** after 5 s and is dropped (`Mover`), instead of waiting forever. Test with a unit outside any navigation region.
5. **Right click and the wheel pass through HUD panels and Gift buttons** to the world (cancel targeting, zoom). Only the left button is consumed. Test.
6. **A click on the fallen prompt** does what Enter does. Test.
7. **Tests leave no orphan nodes.** Fix the tests or helpers that leak (GUT reports them at the end of the run) until the run reports none; add `-gerrors_do_not_cause_failure`-style flags only if GUT needs one to print the count. `ops/test.sh` fails when GUT reports orphans.
8. **Guards that were never tested** (add tests only): a stunned unit resumes an attack order when the stun ends; the calm timer does not advance while paused; Tab does nothing while input is disabled; the `gift_1`, `gift_2` and `cancel` actions and a right mouse click do what `press_gift` and `cancel_targeting` do.

- [ ] **Step 1: Write the tests for items 1–6 and 8** in `tests/core/test_loose_ends.gd`, one or two per item, named after the item. Run them: each for items 1–6 fails first.
- [ ] **Step 2: Fix items 1–6, one commit each** (`fix:` with a subject that says what changed).
- [ ] **Step 3: Item 7** — `test: free everything the tests create` and `chore: fail the test run on orphan nodes`.
- [ ] **Step 4: Run** — `ops/test.sh`, `ops/build-web.sh`, `npx playwright test --trace off`. Expected: all green, no orphans reported.

---

### After the last task: put the milestone online

Once the final review's fixes are in and the suites are green, the controller (not a task implementer) runs `ops/deploy-fly.sh`, checks that https://nocturne-of-ashes.fly.dev/ serves the new build and that the game starts there, and reports the address. The owner has asked for this at the end of every milestone.

---

## Amendments made while building

These decisions changed what the tasks above describe. The code follows the amendments.

- **Test totals.** Review fixes added tests; the suite's own report is the count.
- **Task 1.** The 260-line target for `unit.gd` applied to that task only. The relays from `Orders` are explicit connections; `Unit.drive()` and `face()` are for `Orders` only.
- **Task 2.** Godot strips `--language` from the command-line arguments it reports, so `Main` picks the language only while the engine's locale still equals the system's.
- **Task 3.** Loaded numbers are clamped, never wrapped: vitals to −1…10000, Conscience to 0…10. Álvar is always joined. An empty room or entry makes a save unusable. The save is written to a temporary file and renamed.
- **Task 4.** `Main` is a shell over `Party` (builds members from the state), `Encounter` (the fight flow) and, later, `Conversation`, `Travel` and `WorldHold`. A room without enemies starts cleared. Blood carried into a room is applied as starting Blood, so arriving low does not start the Fury. `Main.state` can be replaced; listeners re-read it on `room_started`.
- **Task 5.** The last checkpoint is also kept in memory and is what a reload uses first, so a browser that cannot write saves does not turn a fall into a wipe. `checkpoint()` does nothing while the title is open.
- **Task 6.** `Interactable.use` returns whether it was used; its collision layer is set when it enters the tree, whatever a scene or subclass says.
- **Task 7.** The add-on is Dialogue Manager 4.2.0. A conversation that goes wrong ends by itself (a refused call, a missing cue, or more than 2 s without a line), is not saved, and the last checkpoint is reloaded. A conversation's hooks are revoked when it ends. Escape does not close a conversation. The add-on's automatic translation-template updates are switched off.
- **Task 8.** A member who joins mid-room stands 2 m from the character of the same name. Learning a Gift keeps running cooldowns.
- **Task 9.** A door's travel is deferred to the end of the frame and re-checked. Doors also refuse during the Fury and while anyone is feeding.
- **Task 10.** A `captive_spared` flag exists. Íñigo's talk changes no state; his opening line changes once the captive is dealt with. Malakor names only the companions still missing.
- **Task 11.** `fresh`, `at`, `title`, `calm` and `frail` work only with `probe=1`. `skirmish=1` never touches a save.
- **After the final review.**
  - Units that are held (pause, conversation, title) stay in the physics world, so they can be clicked while paused.
  - Entering a room that has no enemies restores the party's health (not its Blood): the haven is where the party rests.
  - Characters and doors are Álvar's to use: a click on one with a companion selected sends Álvar.
  - The dialogue box shows how to continue and accepts Space as well as Enter.

## Carried forward

**Milestone 4 (Toledo's look)**
- A controls card reachable from the title; "or click" on the fallen prompt; the cleared line fades; New game asks before erasing a save.
- Any error logged while a conversation looks up its next line ends that conversation: narrow this before visuals are spawned inside a join.
- Keep the camera's focus inside the room: at the waking a third of the screen shows the dark beyond the west wall.
- A character within 2 m of a room's centre puts a joiner on the far side of the centre.

**Milestone 5 (the night of 1212)**
- Extract the session (state, store, checkpoints, title) and the room transition from `Main` before adding rooms, fades and an ending.
- The save has no migration: a version change discards every existing save. Add `migrate(data)` by version, a registry of flags, values other than booleans, state per room beyond one cleared flag, and somewhere for inventory.
- Joining is recorded twice (the joined set and the `*_joined` flags), and the test start `at=vault` copies the flag list by hand.
- Conversations are English only; the HUD follows the system language. Translate them, or offer Spanish only on request until they are.
- "The vault is quiet" is the cleared line for every room. After the vault there is nothing more to do.
- Balance: draining the captive gains little over a sip; the Fury in the haven wounds companions who do not defend themselves.
- A deliberate wait longer than 2 s inside a conversation is cut off by the watchdog.

**Milestone 6 (out the door)**
- The test probe and its page parameters ship in the release build.
