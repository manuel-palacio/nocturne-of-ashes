# Milestone 4: Toledo's Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The capsules and boxes become people and a place: animated, dressed characters; a forge cellar and Roman vaults built from a small kit of stone pieces; torchlight, embers and darkness that hold up in a browser; portraits and a HUD that belong to the setting.

**Architecture:** Nothing about how the game plays changes. Each unit gets a `UnitVisual` child that only reads the unit and shows it: one animated human model shared by every character, coloured by a small palette image and given gear by attachment. Rooms are assembled from kit pieces that Blender scripts generate, textured with CC0 stone, and lit by a few real-time lights over baked or painted darkness. Asset-making tools live in `tools/` and are run by hand; their outputs are committed.

**Tech Stack:** Godot 4.7.2, GDScript, GUT, Playwright, Blender (headless, Python) for the kit, Python with `pygltflib`/`numpy`/`pillow` (through `uv run`) for the character tool, Quaternius "Universal Animation Library" (CC0) for the human model and its animations, Poly Haven / ambientCG textures (CC0), an OFL or Apache-licensed typeface.

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md` (sections "Technical constraints and calls" and "Anti-goals")

**Builds on:** `docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md` and the "Carried forward" sections of all three earlier plans.

## Global Constraints

- Godot **4.7**, GDScript only, rendering method `gl_compatibility`. Web export with threads and extensions off.
- No name, term, text, sound or image from *Vampire: The Masquerade – Redemption* or the World of Darkness.
- Every third-party asset is CC0, CC-BY, OFL, Apache or MIT; each is listed in `CREDITS.md` with its source address, and its licence text is kept beside it. No paid assets and no image-generator art.
- Commits: Conventional Commits, subject 72 characters or fewer, one logical change each, authored as `Manuel <emanuel.palacio@gmail.com>`, ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Typed GDScript, tabs, one class per file with `class_name`.
- **Visuals read, never write.** Nothing under a unit's visual node changes the unit's position, collision, orders, stats or timing. Every gameplay test from earlier milestones passes unchanged, except the few a task names.
- **The browser is the target.** The web build stays under 80 MB on disk and holds 30 frames a second in the existing browser tests; the aim is 60 on a laptop with integrated graphics. No effect may rely on anything the Compatibility renderer lacks (real-time global illumination, volumetric fog, screen-space reflections, decals).
- Textures are at most 1024 px, power-of-two, and compressed for the web export. Models are low to mid poly: a character under 15,000 triangles, a kit piece under 2,000, a whole room under 150,000 on screen.
- Tools are deterministic: running a tool twice gives byte-identical output, so a regenerated asset shows no diff. Tools take their inputs as arguments and write only inside the repository.
- Every player-facing string still goes through translation, with Spanish.
- Test output is clean; the test run fails on orphan nodes.
- Each task that changes what is on screen ends with captured frames that the implementer reads and describes; the controller looks at them too. A task is not done because its tests pass if the frame looks wrong.
- Every task ends with `ops/test.sh` passing in full.

## Review Focus

1. **A unit in every state has a believable picture:** idle, walking, running under Iron Sinew, striking, being hit, stunned, feeding, being fed on, casting, in the Fury, fallen, rising. None shows a T-pose, a frozen frame, a slide without steps, or a model sunk into or floating over the floor. Tests in Task 2; frames in Tasks 2 and 3.
2. **Visual state never lags the game by more than a moment and never sticks:** a unit that dies mid-swing falls; one revived while its death clip plays stands up; a room restart shows no leftover pose; pause freezes animation and unpause resumes it. Tests in Task 2.
3. **Clicks still land:** a character is picked by clicking its body as drawn (the collider and the drawn figure agree within a hand's width), and kit pieces never catch clicks meant for the floor behind them. Tests in Tasks 2 and 6.
4. **Readability in the dark:** each party member, a crusader, a sergeant and a talkable character can be told apart at the default zoom in the darkest corner of each room; the selected member, feedable enemies and doors are marked clearly. Frames in Tasks 3, 6, 7 and 8.
5. **The browser budget:** size, frame rate and load time are measured at the end of every task that adds assets, not only at the end. Task 10 fails the build if the budget is broken.

## File Structure

```
tools/make_character.py            paints the library mannequin by body part, keeps the clips we use
tools/blender/kit.py               generates the stone kit pieces
tools/blender/gear.py              generates swords, shields, helmets, hoods, staff
tools/blender/feed_clip.py         makes the feeding clip if the library has none that fits
tools/render_portraits.gd          renders each character's portrait from the game's own model
assets/characters/human/           human.glb, palette-<name>.png, licence text
assets/gear/                       *.glb
assets/kit/                        *.glb
assets/textures/                   stone, brick, plaster, wood, iron: colour and normal maps
assets/portraits/                  <name>.png
assets/ui/                         typeface, panel frames
src/units/unit_visual.gd           UnitVisual: dress, gear, animation, marks
src/units/dress.gd                 Dress: a character's palette and gear as one resource
resources/dress/*.tres             one per character
src/units/separation.gd            Separation: keeps units from standing inside each other
scenes/rooms/*.tscn                rebuilt from the kit
src/rooms/room_light.gd            flicker and ember helpers, if scripts are needed at all
src/ui/…                           portraits in panels and the dialogue box, theme
tests/visual/…                     one file per task, named in each task
e2e/look.spec.js                   screenshots and budget checks
```

---

### Task 1: The human model and its palettes

**Files:**
- Create: `tools/make_character.py`, `assets/characters/human/human.glb`, `assets/characters/human/palette-*.png`, `assets/characters/human/LICENSE-quaternius-universal-animation-library.txt`, `tests/visual/test_character_asset.gd`
- Modify: `CREDITS.md`, `README.md` (a "Making the art" section)

**What it is.** One rigged, animated human, coloured by an 8 × 1 pixel palette image: every triangle belongs to one body region and looks up that region's square. A character's look is then a palette. The approach and the region logic are proven in the owner's other Godot game; write this tool fresh for medieval dress, do not copy that project's files.

**Interfaces:**
- `tools/make_character.py <path to the library's Godot .glb>` writes `human.glb` and every palette; `--palettes-only` rewrites just the palettes. Run with `uv run --with pygltflib --with numpy --with pillow python3 tools/make_character.py …`. The library file is downloaded by hand from Quaternius (CC0) and is not committed; the README says where from. (It is the "Universal Animation Library", standard edition: its Godot file is `AnimationLibrary_Godot_Standard.glb`, with 46 clips.)
- Regions (palette squares, left to right): `skin`, `hair`, `tunic` (torso and upper arms), `sleeves` (forearms), `skirt` (hips to knee: the hang of a habit, surcoat or robe), `hose` (lower legs), `boots`, `trim` (belt and collar).
- Clips kept, renamed to these exact names (the tool maps library clips to them and fails loudly if one is missing): `idle` (the library's `Idle_Loop`), `walk` (`Walk_Loop`), `run` (`Jog_Fwd_Loop`), `attack` (`Sword_Attack`), `hit` (`Hit_Chest`), `death` (`Death01`), `cast` (`Spell_Simple_Shoot`), `interact` (`Interact`), `stagger` (a loop made from `Hit_Head`, or the nearest fit), `talk` (`Idle_Talking_Loop`), `sit` (`Sitting_Idle_Loop`). Looping clips: `idle`, `walk`, `run`, `stagger`, `talk`, `sit`. The library has no feeding clip; `feed` comes in Task 2.
- Palettes (hex colours are the builder's, within these descriptions):

| Palette | Who | Look |
|---|---|---|
| `alvar` | Brother Álvar | white habit and mantle of a knight-friar, dark hose, brown boots, a red trim |
| `zahra` | Zahra | deep teal robe, ochre sleeves, dark hair covered at the trim |
| `gonzalo` | Gonzalo | grey wool, a brown leather apron as the skirt, bare forearms (skin-coloured sleeves), iron-grey hair |
| `crusader` | crusaders | mail-grey sleeves and hose, a dark red surcoat |
| `sergeant` | sergeants | the same with a bronze surcoat and a darker trim |
| `malakor` | Malakor | black, with a crimson trim; pale skin |
| `smith` | Íñigo | brown, soot-dark apron, bare forearms |
| `captive` | the captive | a torn, dirty undershirt, bare lower legs and feet |

- The model stands 1.8 m tall with its origin at its feet, facing −Z in Godot, under 15,000 triangles, in one mesh with one material slot.

- [ ] **Step 1: Write the failing tests** (6 tests)

```gdscript
# tests/visual/test_character_asset.gd
extends GutTest

const HUMAN := preload("res://assets/characters/human/human.glb")
const CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"attack", &"hit", &"death", &"cast", &"interact", &"stagger", &"talk", &"sit"]
const PALETTES: Array[String] = ["alvar", "zahra", "gonzalo", "crusader", "sergeant", "malakor", "smith", "captive"]

var human: Node3D

func before_each() -> void:
	human = add_child_autofree(HUMAN.instantiate())

func _player() -> AnimationPlayer:
	return human.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

func _mesh() -> MeshInstance3D:
	return human.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func test_it_has_exactly_the_clips_we_use() -> void:
	var names: Array = Array(_player().get_animation_list()).filter(func(n: String) -> bool: return n != "RESET")
	names.sort()
	var expected: Array = CLIPS.map(func(n: StringName) -> String: return String(n))
	expected.sort()
	assert_eq(names, expected)

func test_looping_clips_loop_and_the_others_do_not() -> void:
	for clip: StringName in CLIPS:
		var loops: bool = _player().get_animation(clip).loop_mode != Animation.LOOP_NONE
		assert_eq(loops, clip in [&"idle", &"walk", &"run", &"stagger", &"talk", &"sit"], clip)

func test_it_is_one_mesh_with_one_surface_under_the_triangle_budget() -> void:
	assert_eq(human.find_children("*", "MeshInstance3D", true, false).size(), 1)
	var mesh: Mesh = _mesh().mesh
	assert_eq(mesh.get_surface_count(), 1)
	assert_lt(mesh.get_faces().size() / 3, 15000)

func test_it_stands_on_its_origin_at_human_height() -> void:
	var box: AABB = _mesh().global_transform * _mesh().get_aabb()
	assert_almost_eq(box.position.y, 0.0, 0.05)
	assert_almost_eq(box.size.y, 1.8, 0.1)

func test_every_palette_is_eight_by_one() -> void:
	for palette: String in PALETTES:
		var image: Image = (load("res://assets/characters/human/palette-%s.png" % palette) as Texture2D).get_image()
		assert_eq(image.get_size(), Vector2i(8, 1), palette)

func test_no_two_palettes_are_the_same() -> void:
	var seen: Dictionary = {}
	for palette: String in PALETTES:
		var image: Image = (load("res://assets/characters/human/palette-%s.png" % palette) as Texture2D).get_image()
		var key: String = image.get_data().hex_encode()
		assert_false(seen.has(key), palette)
		seen[key] = true
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh -gtest=res://tests/visual/test_character_asset.gd`.
- [ ] **Step 3: Fetch the library, write the tool, run it, commit its outputs.** Set the palette textures to import without filtering or mipmaps. Run the tool twice and confirm `git status` shows no change after the second run.
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`.
- [ ] **Step 5: Look at it.** Render a line-up of the eight palettes on the model in the idle pose, front and three-quarter, lit plainly (a throwaway Godot scene and `--write-movie`), read the frame and describe each figure. Each must read as a different person at a glance.
- [ ] **Step 6: Commit** — `feat: add the human model, its clips and eight palettes`

---

### Task 2: A visual for every unit

**Files:**
- Create: `src/units/unit_visual.gd`, `src/units/dress.gd`, `resources/dress/*.tres` (one per palette), `tools/blender/feed_clip.py` only if needed, `tests/visual/test_unit_visual.gd`
- Modify: `scenes/units/unit_base.tscn` and the unit scenes, `src/units/unit.gd` (facing and the fallen presentation only), `src/units/orders.gd` (facing only), `tests/units/test_hits_and_revival.gd` (one test, named below), `src/rooms/npc.gd` and `scenes/rooms/npc.tscn`

**Interfaces:**
- Produces: `class_name Dress extends Resource` — `@export var palette: Texture2D`, `@export var gear: Array[PackedScene]` (filled in Task 3), `@export var height: float = 1.8` (the model is scaled to it; Gonzalo 1.9, Zahra 1.7, sergeants 1.88).
- Produces: `class_name UnitVisual extends Node3D` (child `Visual` of every unit, in `unit_base.tscn`; it replaces the capsule `Body`)
  - `@export var dress: Dress`
  - `func clip() -> StringName` (what is playing), `func model() -> Node3D`
  - It reads its parent `Unit` every frame and on its signals, and writes nothing to it. The rules, first match wins:
    1. fallen → `death`, held on its last frame
    2. just risen → `death` played backwards at double speed, then on
    3. drinking (`is_feeding()`) → `feed`
    4. stunned (including being fed on) → `stagger`
    5. a one-shot in progress: `attack` when its melee strikes (`MeleeAttack.hit`), `cast` when it uses a Gift (`GiftUser.gift_used`), `hit` when it is hit (`was_hit`) unless an attack or cast is showing; each for its clip's length, at most 0.7 s
    6. moving faster than 0.1 m/s flat → `run` when its `speed_multiplier()` is above 1, else `walk`, the clip's speed scaled so the feet match the ground speed
    7. otherwise `idle`
  - A character who is speaking in a conversation shows `talk`; the captive shows `sit`. Blends between clips over 0.15 s. The clip `feed` is one more clip added to `human.glb`: the library's nearest fit, or one made by `tools/blender/feed_clip.py` (leaning in over a held victim), added to the tool's kept list and to the asset test.
  - In the Fury the model is tinted red (a shader parameter or material colour on the visual only).
  - Animation runs in the unit's subtree, so the world pause and conversations freeze it.
- `Unit` turns to face where it walks (at most 10 radians a second; attacking still faces the target). The old fallen presentation (laying the capsule down) goes: the death clip is the fall. A fallen unit still leaves every collision layer.
- The unit's collider stays the 0.35 m × 1.8 m capsule. `Npc` uses the same visual with a `Dress` and plays `idle`.
- **Carried from milestone 3.** A conversation ends itself when any error is logged while it looks up its next line (`DialogueRunner`'s error watch). A companion joining inside a conversation now spawns a visual: narrow the watch to errors raised by the add-on or the hooks, and add a test that a join inside a conversation with a deliberately noisy visual (one that logs an error on entering the tree) does not cut the conversation short.
- `tests/units/test_hits_and_revival.gd::test_a_fallen_body_rests_on_the_floor` is replaced by `test_a_fallen_unit_shows_the_death_clip` in the new file; the rest of that file stays.
- Tests that fetch a unit's `Body` node for anything else are reported, not edited.

- [ ] **Step 1: Write the failing tests** (14 tests)

```gdscript
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
	for mesh: Node in _visual(foe).model().find_children("*", "MeshInstance3D", true, false):
		box = box.merge((mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()) if box.size != Vector3.ZERO else (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
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

func test_a_walking_unit_faces_where_it_goes() -> void:
	alvar.order_move(Vector3(6, 0, 0))
	await wait_seconds(0.8)
	var forward: Vector3 = -alvar.global_transform.basis.z
	assert_gt(forward.dot(Vector3(1, 0, 0)), 0.9)

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
```

- [ ] **Step 2: Run to verify failure** — `ops/test.sh`.
- [ ] **Step 3: Implement `Dress`, `UnitVisual`, the facing, the scenes and the `Npc` visual.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`. Expected: all pass; every earlier gameplay test unchanged apart from the one named.
- [ ] **Step 5: Look at it.** Capture frames from the vault skirmish: the party at rest, a melee in progress, a feed, a fallen crusader, a unit in the Fury. Read each and describe posture and legibility. Check a click on a drawn figure's chest and on its head both pick it.
- [ ] **Step 6: Measure.** `ops/build-web.sh`; note the size of `build/web` and run the browser tests (`npx playwright test --trace off`): all pass, frame rate not below 30.
- [ ] **Step 7: Commit** — three commits: `feat: show units as animated people`, `feat: turn units to face where they walk`, `feat: show talkable characters as people`

---

### Task 3: Gear, marks and telling people apart

**Files:**
- Create: `tools/blender/gear.py`, `assets/gear/*.glb`, `tests/visual/test_gear_and_marks.gd`
- Modify: `resources/dress/*.tres`, `src/units/unit_visual.gd`, `src/units/unit.gd` (mark methods only), `src/main.gd` or the node that owns selection (one call), `scenes/units/unit_base.tscn`

**Interfaces:**
- `tools/blender/gear.py` (run as `blender -b -P tools/blender/gear.py`) generates, each under 600 triangles, flat-coloured with vertex colours or one shared small texture: `sword`, `shield` (a kite shield), `helmet` (a nasal helm), `mail_coif`, `hood`, `staff`, `hammer`.
- **Cloth pieces**, from the same tool, because colour alone leaves every figure in tights (the model has separate legs): `skirt_long` (a habit's or robe's skirt, hip to ankle, a slightly flared tube open at the bottom), `skirt_short` (a surcoat's, hip to knee), `apron` (a flat front panel, chest to knee), `mantle` (a cloak hanging from the shoulders down the back to the calf), `veil` (a head cloth covering the hair, falling to the shoulders). They are rigid pieces attached to a bone (hips for skirts and apron, the upper spine for the mantle, the head for the veil), wide enough that the legs stay inside while walking and running at the game's camera distance; a foot showing through at full stride is accepted. Each takes its colour from the character's palette (the `skirt` square for skirts and apron, `tunic` for the mantle unless the dress says otherwise, `trim` for the veil), so a `Dress` lists pieces, not colours.
- `Dress.gear` attaches pieces to named bones through `BoneAttachment3D` (the tool documents each piece's bone and offset): Álvar long skirt, white mantle, sword and shield; Zahra long skirt, veil and staff; Gonzalo apron and hammer; crusaders short skirt, helmet, sword, shield; sergeants short skirt, helmet, mail coif, sword, a larger shield; Malakor long skirt, a dark mantle, sword; Íñigo apron and hammer; the captive nothing.
- Marks, all drawn by the visual and all readable against any body colour and in the dark (unshaded, with a dark outline or drawn on the floor):
  - **Selected:** a thin gold ring on the floor under the selected party member. `Unit.set_selected_mark(on)`, `has_selected_mark()`; the selection owner keeps exactly one lit.
  - **Can be fed on:** replaces the red sphere: a pale drop above the head with a dark outline, bobbing slowly. `set_feed_mark` / `has_feed_mark` keep their names.
  - **Can be talked to or used:** a small pale ring on the floor under an `Npc` or in front of a `Door` while the mouse is over it (hover), and always for the nearest one within 4 m of the selected member.

- [ ] **Step 1: Write the failing tests** (8 tests): each character's dress has the gear listed above (by scene file name); gear nodes sit under `BoneAttachment3D`s; exactly one party member carries the selected mark and it follows selection, restart and a companion's fall; the feed mark still follows `can_feed_on` (the existing feed-mark tests pass unchanged); the hover mark shows for an `Npc` under the cursor and hides when the cursor leaves; a fallen unit shows no marks. Write them in the style of `tests/core/test_feed_marks.gd`.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Write the gear tool, run it, attach the gear, add the marks.**
- [ ] **Step 4: Run to verify pass** — `ops/test.sh`.
- [ ] **Step 5: Look at it.** A frame of the vault with the party and both enemy kinds at the default zoom, in the room's darkest area; a frame with a feed mark over a crusader in dark red; a frame of the haven with all five people. In each, name who is who from the picture alone. If two figures cannot be told apart, change palette or gear until they can.
- [ ] **Step 6: Measure** as in Task 2.
- [ ] **Step 7: Commit** — `feat: give characters gear`, `feat: mark the selected, the feedable and the usable`

---

### Task 4: Nobody stands inside anybody

**Files:**
- Create: `src/units/separation.gd`, `tests/units/test_separation.gd`
- Modify: `scenes/units/unit_base.tscn`, `src/units/unit.gd` (one call in the movement step)

**Interfaces:**
- Produces: `class_name Separation extends Node` (child of a unit): each physics frame it returns a small push away from other living units closer than `@export var radius: float = 0.7` (flat), at most `@export var strength: float = 2.0` m/s, which `Unit` adds to its horizontal velocity before `move_and_slide`. It never pushes a unit that is feeding, being fed on or stunned, and never moves a unit through a wall. Units still do not collide with each other physically.
- It must not break: chasing into melee range (1.6 m is outside the radius), the stall check for move orders, feeding (which needs melee range), arrival within 0.5 m of an ordered point when nobody stands there, and interact orders.

- [ ] **Step 1: Write the failing tests** (6 tests): two idle units placed on the same spot end at least 0.6 m apart within 2 s; three attackers on one target end with no pair closer than 0.5 m while all three keep striking; a unit ordered to a point where another stands idle arrives within 1.0 m and its order ends (no stall warning); a feeder and its meal are not pushed apart; a unit beside a wall is not pushed through it; the existing chase, melee, feeding and interact tests pass unchanged.
- [ ] **Step 2–4:** fail, implement, pass.
- [ ] **Step 5: Look at it.** A frame of three party members attacking one sergeant: three distinct figures around it.
- [ ] **Step 6: Commit** — `feat: keep units from standing inside each other`

---

### Task 5: The stone kit

**Files:**
- Create: `tools/blender/kit.py`, `assets/kit/*.glb`, `assets/textures/*` with licence texts, `tests/visual/test_kit.gd`
- Modify: `CREDITS.md`, `README.md`

**Interfaces:**
- `blender -b -P tools/blender/kit.py` generates the pieces on a 2 m grid, origin at the floor centre of each piece's footprint, each with a simple collision shape authored as a `-col` or `-colonly` child where the piece blocks movement:

| Piece | What |
|---|---|
| `floor_slab` | 2 × 2 m worn flagstones |
| `wall` | 2 m wide, 4 m tall coursed stone, one-sided |
| `wall_brick` | the same in Roman brick, for the vault |
| `pillar` | 0.8 m square pier with a plain capital, 4 m |
| `arch_horseshoe` | a horseshoe arch spanning 2 m between two piers, in alternating stone and brick voussoirs |
| `arch_round` | a Roman round arch spanning 4 m |
| `vault_barrel` | a 4 × 2 m segment of barrel vault, open underneath, one-sided from below |
| `door_frame` and `door_leaf` | a studded wooden door in a stone frame, 1.4 × 2.4 m |
| `stair_down` | a flight going down into darkness, 2 m wide (a set piece, not walkable) |
| `forge` | a raised hearth with a hood |
| `anvil`, `rack`, `barrel`, `bench`, `bars` | props; `bars` is an iron grille 2 m wide |
| `sconce` | an iron torch bracket |
| `lock_seal` | a great iron lock on a slab, for the last door |

- Textures: five tiling sets at 1024 px (stone blocks, Roman brick, plaster, wood, iron), colour and normal maps, from Poly Haven or ambientCG (CC0), each credited. Pieces share them; a piece adds no texture of its own.
- A horseshoe arch must read as one: the curve continues below its centre line. This is the look that says Toledo.

- [ ] **Step 1: Write the failing tests** (5 tests): every piece in the table exists and loads; each is under 2,000 triangles; each fits its stated footprint and height within 5 cm; blocking pieces have a collision shape and props that do not block have none; no piece carries an embedded texture larger than the shared sets.
- [ ] **Step 2–4:** fail, write the tool and fetch the textures, run it twice (no diff the second time), pass.
- [ ] **Step 5: Look at it.** A contact sheet: every piece on a grey floor under plain light, with a 1.8 m character beside it for scale. Describe each.
- [ ] **Step 6: Measure** as in Task 2.
- [ ] **Step 7: Commit** — `feat: add the stone kit and its textures`

---

### Task 6: The vault becomes the Cave of Hercules

**Files:**
- Create: `tests/visual/test_vault_look.gd`
- Modify: `scenes/rooms/vault_room.tscn`, `scenes/main.tscn` or the camera rig's settings, `src/player/camera_rig.gd` only if a default must change (its tests then change with it, named in the report)

**The room.** The same footprint and the same gameplay positions (24 m × 16 m, every `Entry_*`, `Companion*`, `EnemySpawn*`, door and pillar position within 0.5 m of where it is now, so no gameplay test moves): Roman brick walls, two rows of piers carrying round arches along the length, barrel vaulting implied above them (the camera looks down through it: vault segments are one-sided from below and so invisible from above), flagstone floor, the west door, the last lock at the east end with its seal, sconces where the torches are. The navmesh is rebaked from the new colliders and stored.

**The camera.** Keep the camera's focus inside the room: the rig follows its target but its focus point is clamped to the room's floor rectangle shrunk by a margin, so the view never centres on the dark beyond a wall (at a new game's start a third of the screen was black). `Room` exposes its floor bounds; the rig takes them at room start. Test: with the target at a room's corner the focus point stays inside the bounds, and in the middle of the room it equals the target. Revisit the pitch and the heights with real pieces: the carried complaint is that pillars lean 15–20° at the screen edges and wall tops crowd the view. Try a steeper pitch (55–60°) with the long lens, and pier and wall heights of 3 m; choose by looking. Whatever changes, clicks near the camera-side wall still land (the existing near-wall tests pass).

- [ ] **Step 1: Write the failing tests** (5 tests): every marker and door is still on the navmesh and within 0.5 m of its old position (positions listed in the test from the current scene); the room uses kit pieces only (no `BoxMesh` or `CapsuleMesh` left in the room scene); a click on the floor between two piers orders a move there (kit pieces do not catch it); the room has at most six real-time lights of which at most two cast shadows; the room's drawn triangle count is under 150,000.
- [ ] **Step 2–4:** fail, rebuild the room, pass. All earlier tests that use the vault pass unchanged.
- [ ] **Step 5: Look at it.** Frames at spawn, mid-room during the fight, and at the last lock, plus one with the camera turned 90°. Describe each; say what the lean at the screen edge is now.
- [ ] **Step 6: Measure** as in Task 2.
- [ ] **Step 7: Commit** — `feat: rebuild the vault from the stone kit`, and `feat: steepen the camera` if it changed

---

### Task 7: The forge-haven

**Files:**
- Create: `tests/visual/test_haven_look.gd`
- Modify: `scenes/rooms/forge_haven.tscn`

**The room.** A swordsmiths' cellar under Toledo, same footprint and same gameplay positions as now: stone walls with two horseshoe arches opening onto shallow alcoves, the forge with its hood against the north wall and a glow from the hearth, the anvil and rack, benches and barrels, the captive's alcove closed by iron bars with a gap to speak through, the stair door at the east wall with `stair_down` beyond it. Everyone stands where they stood.

- [ ] **Step 1: Write the failing tests** (4 tests): markers, people and the door within 0.5 m of their old positions and on the navmesh; kit pieces only; every `Npc` can still be reached and used (an interact order on each completes); light and triangle limits as in Task 6.
- [ ] **Step 2–4:** fail, rebuild, pass. The story tests pass unchanged.
- [ ] **Step 5: Look at it.** Frames at the waking (dialogue box open), of the forge with Malakor, of the captive behind his bars, and of the stair door. Describe each.
- [ ] **Step 6: Measure** as in Task 2.
- [ ] **Step 7: Commit** — `feat: rebuild the forge-haven from the stone kit`

---

### Task 8: Light, dark and air

**Files:**
- Create: `src/rooms/room_light.gd` if a script is needed, `tests/visual/test_atmosphere.gd`
- Modify: both room scenes, `scenes/main.tscn` (environment), `project.godot` if a rendering setting changes

**What is wanted.** Pools of warm torchlight in real darkness; the forge as the brightest thing in the haven; stone that shows its relief; a little air: embers rising from the forge and torches, dust in the light. Characters stay readable in the dark (Review Focus 4).

**How, in order of preference; each step says what was tried and what was kept:**
1. **Baked lighting.** Try Godot's `LightmapGI` for each room: bake on this machine (it has a display session and a GPU) from the editor or an editor script, commit the baked data, and check it renders in the Compatibility renderer in the browser and what it costs in size. Keep it only if it works in the browser test, adds under 8 MB per room, and the bake can be repeated from one documented command.
2. If that fails: **painted darkness.** Vertex colours or a per-room occlusion texture generated by the kit tool or a small Blender bake, multiplied into the stone material, with the real-time torches on top.
3. In either case: at most six real-time lights a room, two with shadows; a flicker on torches; `GPUParticles3D` only if they run in the browser at no visible cost (else `CPUParticles3D`), at most 200 particles a room; tone mapping and colour adjustment in the environment (a slight cool lift in the shadows, warm highlights); a low ground haze made of a few large, soft, unshaded quads if it looks right. No distance fog measured from the camera.

- [ ] **Step 1: Write the failing tests** (4 tests): light and particle counts within the limits in both rooms; the environment has no camera-distance fog; the web export contains whatever the chosen lighting needs (a baked-data file exists and is in the export, or the occlusion textures are); pausing the world freezes particles and flicker with the units (or deliberately does not: say which and test it).
- [ ] **Step 2–4:** fail, do the lighting, pass.
- [ ] **Step 5: Look at it.** For each room: one frame of its brightest place and one of its darkest with the party standing in it. In the darkest, every party member must still be distinguishable; if not, add a faint rim or lift on characters rather than more room light.
- [ ] **Step 6: Measure** as in Task 2, in both browsers, and report frame rates before and after this task.
- [ ] **Step 7: Commit** — one commit per kept technique, for example `feat: bake the rooms' lighting`, `feat: add embers and dust`

---

### Task 9: Portraits and a HUD that belongs

**Files:**
- Create: `tools/render_portraits.gd`, `assets/portraits/*.png`, `assets/ui/*` (typeface and its licence, panel frame textures), `resources/ui/theme.tres`, `tests/ui/test_portraits_and_theme.gd`
- Modify: `scenes/ui/*.tscn`, `src/ui/*.gd`, `CREDITS.md`

**Interfaces:**
- `godot --path . -s tools/render_portraits.gd` renders a 256 × 256 head-and-shoulders portrait of each dressed character (the game's own model, palette and gear, in a three-quarter view, lit from one side, on a dark ground) to `assets/portraits/<palette>.png`. Deterministic.
- A portrait appears: in each party panel (64 px, replacing the colour swatch); in the dialogue box beside the speaker's name (128 px) when the speaker has one (matching by the `Npc`'s dress, or by speaker name for party members); on the title screen, Álvar's, large and dim.
- One theme for every control: a serif or blackletter-leaning text face that stays readable at 16 px (OFL or Apache, credited), dark panels with a thin worn-metal edge, health in blood red and Blood in a deeper, colder red that can still be told apart from health (shape or position as well as colour: the two bars differ in height). Buttons show hover and disabled states.
- Party panels and Gift buttons change their text and bars only when values change, not every frame (carried from milestone 2).
- Nothing takes keyboard focus; clicks behave exactly as before.
- **Carried from milestone 3**, all translated:
  - A **controls card**: a `Controls` button on the title and a `?` button in the HUD's corner open one panel listing the controls (move and attack, feed, select, Gifts, pause, camera, talk, doors, restart); Escape, a click outside, or the button closes it; while it is open the world is held like a pause.
  - The fallen prompt reads `You have fallen — press Enter or click` (the existing tests that compare the old text change to the new one: name them in the report).
  - The cleared line fades after 4 s instead of staying until the room changes.
  - **New game asks first** when a usable save exists: the first press turns the button into `Erase the saved game?` with `Yes, begin anew` and `No`; with no save it starts at once.

- [ ] **Step 1: Write the failing tests** (6 tests, plus one or two for each carried item above): a portrait file exists for each of the eight palettes at 256 × 256; each party panel shows its member's portrait; the dialogue box shows the speaker's portrait for Malakor and none for an unknown speaker; every control in the HUD, dialogue box and title uses the theme; a panel's label is not reassigned while nothing changes (count assignments over 30 frames through a small test hook or by watching a signal); the existing HUD, dialogue and title tests pass unchanged.
- [ ] **Step 2–4:** fail, render, theme, pass.
- [ ] **Step 5: Look at it.** Frames of the vault HUD mid-fight, the dialogue box on a choice with a portrait, and the title. Read every piece of text in each frame back in the report: if it cannot be read from the frame, it is too small or too faint.
- [ ] **Step 6: Measure** as in Task 2.
- [ ] **Step 7: Commit** — `feat: render character portraits`, `feat: theme the HUD, the dialogue box and the title`

---

### Task 10: The browser budget

**Files:**
- Create: `e2e/look.spec.js`, `ops/check-budget.sh`
- Modify: `export_presets.cfg` (texture compression, excludes), `README.md`

**Interfaces:**
- `ops/check-budget.sh` fails when `build/web` is over 80 MB or when any single file other than the engine's `.wasm` is over 30 MB, and prints the ten largest assets inside the pack.
- `e2e/look.spec.js`, in both browsers:
  - the skirmish reaches 30 frames a second or more with the whole party and six enemies in view, measured after ten seconds of fighting;
  - the story's haven does the same with all five people in view;
  - time from navigation to `nocturneStarted` is under 20 s on this machine for a first load;
  - it saves frames to `build/e2e/look-*.png`: the title, the waking, the haven's forge, the vault at spawn, the vault mid-fight, a feed, the last lock.
- Anything in the pack that the game never loads is removed or excluded.

- [ ] **Step 1: Write the browser tests and the budget script; run them; expect failures where the budget is broken.**
- [ ] **Step 2: Fix what breaks the budget** (texture sizes and compression, unused clips or pieces, light counts), re-measuring after each change.
- [ ] **Step 3: Run everything** — `ops/test.sh`, `ops/build-web.sh`, `ops/check-budget.sh`, `npx playwright test --trace off`. Expected: all green.
- [ ] **Step 4: Look at it.** Read all seven saved frames and describe each; these are the frames the owner will be shown.
- [ ] **Step 5: Commit** — `test: hold the browser build to its size and frame-rate budget`

---

### Task 11: Loose ends carried for this milestone

Each item is one small change with its test, in `tests/visual/test_loose_ends.gd` or the file that fits.

1. **Camera follow without jitter.** Turn on physics interpolation for units (or move the camera follow to the physics step) and confirm by test that the camera's distance to its target changes smoothly frame to frame while the target walks.
2. **Gift numbers in one place.** Each Gift's numbers live only in its resource; the script's defaults are neutral, and a test loads every Gift resource and checks it against the design table.
3. **Navigation that is not flat.** The mover re-measures the height between a unit's feet and the navmesh along the walk, not once per order; a test walks a unit across a fixture with a 0.4 m step up joined by a ramp.
4. **The agent radius** used to bake every room is the one the units use (0.4 m, with a bake cell size that does not round it up), checked by a test on each room's stored navmesh settings.
5. **An order that waits for a landing that never comes** is dropped with one warning after 5 s.

- [ ] **Step 1: Write the tests; each fails first.**
- [ ] **Step 2: Fix each item in its own commit.**
- [ ] **Step 3: Run** — `ops/test.sh`, `ops/build-web.sh`, `npx playwright test --trace off`.

---

### After the last task: put the milestone online

Once the final review's fixes are in and the suites are green, the controller runs `ops/deploy-fly.sh`, checks that https://nocturne-of-ashes.fly.dev/ serves the new build and that the game starts there, and reports the address with the frames from Task 10.

---

## Amendments made while building

These decisions changed what the tasks above describe. The code follows the amendments.

- **Task 1.** The character tool's command pins its Python and library versions (the README has it). The library has 46 clips; the model keeps only the 13 the game plays (`feed` and `sit_talk` came later).
- **Task 1.** Cloth shapes (habit skirt, robe, mantle, apron) are gear pieces built in Task 3, not palette colours: the mannequin has separate legs, so a "skirt" colour reads as breeches. Zahra's hair covered at the trim was dropped.
- **Task 2.** No backtrace-based error watch inside conversations: the party reacts to joins and learned Gifts deferred, so no scene change runs inside a line lookup, the same in debug and release. A joiner appears one frame after the line that calls `join`.
- **Task 2.** Travel plays the `run` clip above 2.2 m/s and `walk` below (the walk clip at 4 m/s is a shuffle); two tests changed to match.
- **Task 2.** A feeder's figure may be drawn shifted towards its victim, up to 0.8 m and within its own visual, because figures 1.5 m apart do not read as feeding; the unit itself does not move.
- **Task 2.** The captive sits on a stool and talks with a `sit_talk` clip.
- **Task 3.** Cloth bends with shape keys, beyond the plan's rigid pieces, on condition that it is cheap: tables precomputed by the tool, weights written only on change, skipped off screen and when settled.
- **Task 3.** Only one use ring shows at a time: the hovered thing, else the nearest within 4 m, with a 0.5 m margin against swapping. It shows on a barred door, not on an unwired door or on someone who cannot be talked to now.
- **Task 3.** The hood piece was removed, unused.
- **Task 4.** The separation radius is 0.9 m, not 0.7: at the game's camera units 0.67 m apart still read as one knot.
- **Task 4.** Beyond separation alone, a pushed-away attacker walks back in, and attacks are made from a ring 1.25–1.55 m from the target; without them the wider radius left attackers out of reach.
- **Task 4.** Followers re-follow at their follow distance plus 2 m while the leader stands still and plus 1 m while it walks (remembered for 0.6 s); a follow walk under way is finished. Resting followers stay put; a leader walking away is followed as before.
- **Task 5.** Textures import as Basis Universal, so desktop GPUs without S3TC can draw them.
- **Task 5.** The stair down is a set piece: wall-layer barriers keep units off it and no world-layer body sits above the floor, so a click on it lands at floor level. The door does the travelling.
- **Task 6.** Figures stand about 90 px tall at the default camera distance, not 100–120: closer broke two browser tests' framing, and the wheel zooms in to about 180 px.
- **Task 6.** "Cut them at that side" is `CameraCut`: the camera-side arcade and wall are not drawn; their colliders stay.
- **Task 7.** The captive's grilles are not cut: the captive behind bars is the picture, and thin bars hide little.
- **Task 7.** Making the haven's horseshoe arches read was moved to Task 8, as a question of light and framing.
- **Task 7.** A door draws its leaf exactly while an exported node it is set in (its frame) is drawn, one pattern for both rooms. The final fix wave extended it to other parts of a door, such as the last lock's seal; a sealed door shows no leaf.
- **Task 8.** No dust in the air, only embers: the dust's shader compile broke the Firefox load budget.
- **Task 9.** While the controls card is open no input reaches the game, stricter than the pause: the card covers the screen.
- **Task 9.** The portraits are waist-up dressed mannequins with smooth faces, and Álvar has no hood: the model has no face and the dresses no cowl.
- **Task 10.** The title is never dead: shaders are compiled over several frames behind a "preparing" line, New game works at once, and a test holds that path to 15 s.
- **Task 10.** Warm-up frames of up to about 2.7 s in Firefox are accepted: one shader's two programs link in one frame and cannot be split.
- **Task 10.** The camera keeps 220 px clear for the party panels; 320 px moved an earlier browser test's clicks. A selection ring may touch the panels' edge.
- **Commits.** Commit types are the seven in the rules; `perf:` and `build:` commits were reworded, two of them after they had been pushed, with the owner's agreement to rewrite the public branch once.
- **Final fix wave.** The credits name the Godot Engine, and every web build serves `credits.txt` and `licenses.txt` (the engine's licence and notices, then every licence file the credits name). The dialogue hint names the number of choices; the keypad's Enter confirms. A browser test walks the story from New game to the last lock and back by Continue.

## Carried forward

- Faces are featureless and the portraits show bare-torso mannequins: the model has no face.
- Melee reads as a knot of rigid skirts.
- The floor texture's repeat shows, and the piers' faces on the camera side are near black.
- The camera cut pops at 60° of turn.
- Warm-up frames of up to 2.7 s in Firefox.
- The vault's west door is seen edge-on.
- The party panels or the dialogue box can cover a character.
- Units can stand inside the people they talk to (`Npc`).
- Conversations are not yet translated (milestone 5).
- The `?probe=1` test parameters are open on the public site.
- `ops/bake-light.sh` has not been run end to end since its last edit.
- The texture path for GPUs without S3TC has never run on real hardware.
- `unit_visual.gd` is due for a split.
