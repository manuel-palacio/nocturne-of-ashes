# Milestone 5a: Faces and Clothes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every character has a face and real clothes: no blank head and no bare muscled torso anywhere in play, in a portrait or on the title.

**Architecture:** Nothing about how the game plays changes. The mannequin is built of rigid pieces that each follow one bone, and gear is already hung from bones; heads and garments are more gear of that kind, made by Blender scripts from small per-character tables and coloured from the character's palette. The mannequin's own head is taken out of the model, so every dress names a head.

**Tech Stack:** Godot 4.7.2, GDScript, GUT, Playwright, Blender 5.3 (headless, Python) for heads and garments, Python with `pygltflib`/`numpy`/`pillow` (through `uv run`, pinned) for the character tool.

**Spec:** `docs/superpowers/specs/2026-11-21-character-art-design.md`; the game's design is `docs/superpowers/specs/2026-11-15-vertical-slice-design.md`.

**Builds on:** `docs/superpowers/plans/2026-11-16-milestone-4-toledos-look.md` (its "Amendments made while building" and "Carried forward").

## Global Constraints

- Godot **4.7**, GDScript only, rendering method `gl_compatibility`. Web export with threads and extensions off.
- No name, term, text, sound or image from *Vampire: The Masquerade – Redemption* or the World of Darkness. The game's own terms: the Turning, the Blood, Rites, Alma, the Silence, the Fragua, the Sangre, the Fury.
- Nothing downloaded is added. No paid assets and no image-generator art. Anything third-party already in the tree stays credited in `CREDITS.md`.
- Commits: Conventional Commits with the types feat, fix, test, docs, refactor, chore, ci only; subject 72 characters or fewer; one logical change each; authored as `Manuel <emanuel.palacio@gmail.com>`; ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Typed GDScript, tabs, one class per file with `class_name`.
- **Visuals read, never write.** Nothing under a unit's visual node changes the unit's position, collision, orders, stats or timing. Every earlier test passes unchanged, except the few a task names.
- **The look stays faceted and painted flat:** planes and a few painted features, closer to a carved saint than a photograph. No smooth realistic faces.
- **No new shader variant.** Every new piece is drawn with the same kind of material as the body (the palette texture, a UV offset, the emission lift); two-sidedness is made in geometry, not by the material.
- A dressed character stays under 15,000 triangles; a head under 900, a garment piece under 600. The web build stays under 80 MB; the browser tests' 30 frames a second holds (the aim is 60).
- Tools are deterministic and pinned: a second run gives byte-identical output. Blender tools refuse another Blender version. Tools write only inside the repository.
- Saves keep loading; the portraits keep their file names (`assets/portraits/<palette>.png`) and the speaker table its keys.
- Every task that changes what is on screen ends with captured frames under `build/shots/` that the implementer opens and describes plainly, including what looks wrong; the controller looks too.
- Every task ends with `ops/test.sh` passing in full, with clean output and no orphans.

## Review Focus

1. **Nothing of the mannequin shows that should not:** no blank head, bare chest, or skin-coloured muscle between garment pieces, in any of the 13 clips (the bends are the test: `attack`, `cast`, `feed`, `sit`, `death`, `run`). Frames per clip in Task 2; a test that every dress covers the torso and names a head.
2. **Pieces do not tear or float:** at elbows, shoulders, neck and waist, in the bent clips, garments overlap enough that no gap opens and nothing hovers off the body by more than a few centimetres. Frames in Task 2.
3. **A figure with no head or an unknown piece fails loudly, not silently:** a dress without a head is an error a test catches; the game still draws the figure.
4. **Readability holds:** the eight are told apart at the game camera in the dark corner and in a 64 px portrait; the selected ring, the feed mark, the Fury tint, the hit flash and the dead still read on clothed figures. Frames in Tasks 2 and 3.
5. **The browser budget:** triangles per character, build size, frame rate in the six-enemy fight, and the Firefox start (no new shader, the warm-up still covers every piece) are measured in Task 4.

## File Structure

- `tools/make_character.py` — also removes the mannequin's head; palettes may grow from 8 to 16 squares.
- `tools/blender/heads.py` (new) — builds `assets/gear/head_<name>.glb` from a table per character.
- `tools/blender/gear.py` — also builds the garment pieces.
- `src/units/dress.gd`, `src/units/gear_piece.gd`, `src/units/unit_visual.gd` — a dress names its head; wearing more pieces. If `unit_visual.gd` grows, split wearing (gear, cloth scheduling) into its own class as milestone 4's notes ask.
- `resources/gear/*.tres`, `resources/dress/*.tres` — the new pieces and who wears them.
- `tools/render_portraits.gd`, `assets/portraits/*.png` — rendered again.
- `tests/visual/test_faces_and_clothes.gd` (new), and the existing visual tests where they count pieces or palettes.

---

### Task 1: Heads

**Files:**
- Create: `tools/blender/heads.py`, `assets/gear/head_<name>.glb` for alvar, zahra, gonzalo, malakor, smith, captive, crusader, sergeant, `resources/gear/head_<name>.tres`, `tests/visual/test_faces_and_clothes.gd`
- Modify: `tools/make_character.py`, `assets/characters/human/*`, `src/units/dress.gd`, `src/units/unit_visual.gd`, `resources/dress/*.tres`, tests that pin the model's triangle count or the palette's size

**Interfaces:**
- Produces: `Dress.head: GearPiece` (hung from `DEF-head`; coloured from the wearer's palette). `blender -b --factory-startup -P tools/blender/heads.py` writes all eight heads. `UnitVisual` hangs the head like any gear, first.
- Consumes: `GearPiece`, `UnitVisual._hang_gear()`, the palette layout in `tools/make_character.py`.

**What a head is.** One rigid piece modelled in the model's frame at rest with its origin at the head bone, from the neck's top up: a skull with planes for brow, cheekbones, jaw and chin, a nose with a bridge, eye sockets, ears, and hair as geometry (cut, tonsure, bald, long, a beard). The table per character gives the proportions and the choices; the eight differ in silhouette, not only in colour:

| character | head |
|---|---|
| Álvar | lean, young, a tonsure ring of brown hair, clean-shaven |
| Zahra | fine-boned, dark brows; her veil (existing piece) frames the face and must still fit |
| Gonzalo | broad, heavy jaw, bald crown, grey beard |
| Malakor | long, gaunt, hollow cheeks, pale, black hair to the shoulders |
| Íñigo (smith) | square, short dark hair, stubble |
| the captive | narrow, hair matted, unshaven |
| crusader | plain soldier's face; the mail coif (existing) must fit over it |
| sergeant | older soldier, moustache; the helmet (existing) must fit over it |

Eyes, brows and mouth are painted: faces of the mesh whose texture coordinates point at their own squares of the palette. The palette may grow from 8 to 16 squares (still one row, power-of-two) for eye white, iris, brow, lips and beard; every place that knows the count (`PALETTE_SQUARES`, the tool, the cloth material's offset, tests) follows. The mannequin's own head (the triangles its head bone moves, above the neck joint) is removed from `human.glb`.

- [ ] **Step 1: Write the failing tests** in `tests/visual/test_faces_and_clothes.gd`: every dress in `resources/dress/` has a head whose bone is `DEF-head`; `human.glb` has no triangle above the neck joint's top (the height is named in the test from the tool's constant); each head is under 900 triangles and its bounds lie within 0.16 m of the head bone sideways and 0.3 m upward (hair and beard included; Malakor's hair may reach 0.3 m down); a dress with no head logs one error and the figure is still built; a dressed figure's head follows the head bone in the `feed` clip (its transform changes with the bone's).
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Build the tool, the heads, the resources; remove the mannequin's head; wear the head.**
- [ ] **Step 4: Run the tests and the full suite.** Tests that pinned the model's triangle count or eight palette squares change to the new numbers: name each in the report.
- [ ] **Step 5: Look at it.** `build/shots/heads-lineup.png` (all eight, front, shoulders up, even light), `heads-profile.png` (side), `heads-game.png` (the party and two soldiers at the game camera in the vault), and one frame each of `feed`, `sit` and `death`. Describe each; say which two heads are hardest to tell apart.
- [ ] **Step 6: Run both tools twice; no diff. Measure the build.**
- [ ] **Step 7: Commit** — `feat: take the mannequin's head off the model`, `feat: build a head for each character`, `feat: wear a head from the dress`

---

### Task 2: Garments

**Files:**
- Modify: `tools/blender/gear.py`, `assets/gear/*`, `resources/gear/*.tres`, `resources/dress/*.tres`, `src/units/unit_visual.gd` (and a new class if wearing is split out), `tests/visual/test_faces_and_clothes.gd`, tests that count a dress's pieces

**Interfaces:**
- Consumes: `GearPiece` (rigid, hung from one bone; cloth coloured by a palette region; shape tables for cloth that bends), `Dress.head` from Task 1.
- Produces: garment pieces in `assets/gear/` and their `resources/gear/*.tres`; every dress covers its torso and arms.

**What a garment is.** Rigid shells, each following one bone like the mannequin's own segments, modelled a little outside the body so nothing of it shows: a chest piece, an abdomen piece overlapping it and the skirt's top, upper sleeves, lower sleeves, a collar or cowl at the neck. Pieces overlap their neighbours by enough to stay closed in every clip. Where cloth hangs it uses the shape tables and the cloth fit that skirts and the mantle use now.

| character | wears |
|---|---|
| Álvar | a white habit: chest and abdomen with a scapular panel front and back, wide sleeves, a cowl lying on the shoulders, the long skirt; rope belt. His mantle goes (the cowl replaces it) unless it reads better kept |
| Zahra | a teal robe with fitted sleeves and a sash, the veil, the long skirt |
| Malakor | a black robe, high collar, long narrow sleeves, the long skirt, a crimson sash |
| Gonzalo | a grey tunic with rolled sleeves (forearms bare), the leather apron |
| Íñigo | a brown tunic, sleeves to the elbow, the apron |
| the captive | a torn off-white shirt open at the neck, ragged short sleeves |
| crusader | a red surcoat over mail sleeves, the coif |
| sergeant | an ochre surcoat over mail sleeves, the helmet over a coif |

Bare forearms and hands are skin and are the mannequin's; that is wanted for the smiths. A bare chest is wanted for nobody.

- [ ] **Step 1: Write the failing tests:** every dress has a piece hung from each of the chest bone, the abdomen (lower spine) bone and both upper-arm bones (the bones are named in the test from the tool's table); every new piece is under 600 triangles and each dressed character under 15,000; every cloth piece with shape keys has its table; in each of the clips `attack`, `cast`, `feed`, `sit`, `death` and `run`, sampled at five times, no vertex of a chest or abdomen piece is more than 0.08 m from the bone segment it covers (nothing floats) and adjacent pieces' bounds overlap (nothing tears); a figure's materials are all the body's kind (same class, same feature flags), counted.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Build the pieces and dress the eight.** Keep `UnitVisual`'s cloth scheduling cheap: pieces without shape keys cost nothing per frame.
- [ ] **Step 4: Run the tests and the full suite.** Tests that count a dress's pieces change: name each.
- [ ] **Step 5: Look at it.** `build/shots/clothes-lineup.png` (all eight, full figure, front and back), a strip per character of the six bent clips (`clothes-<name>-clips.png`), `clothes-fight.png` (the vault mid-fight at the game camera), `clothes-dark.png` (the darkest corner), `clothes-fury.png`, `clothes-dead.png`. Say plainly where skin shows that should not, where a piece floats or cuts through another, and whether the melee reads better or worse than before.
- [ ] **Step 6: Run the tool twice; no diff. Measure the build and the fight's frame rate (`npx playwright test --trace off`).**
- [ ] **Step 7: Commit** — `feat: build habits, robes, tunics and surcoats`, `feat: dress the eight in their clothes`

---

### Task 3: Portraits and the title

**Files:**
- Modify: `tools/render_portraits.gd`, `assets/portraits/*.png`, the title's portrait, `tests/ui/test_portraits_and_theme.gd` if it pins framing, `README.md`

- The portraits go back to head and shoulders: three-quarter view, one warm light from the side and a faint cool fill, dark ground, 256 px; the title's Álvar at 512 px with its soft edge, cowl visible.
- [ ] **Step 1: Write the failing test:** each portrait differs from every other by more than a threshold in a 32 × 32 downscale (they are not the same picture recoloured), and the middle third of each holds both skin and the two eye squares' colours (a face is in frame).
- [ ] **Step 2–4:** fail, render, pass; full suite.
- [ ] **Step 5: Look at it.** `build/shots/portraits-sheet.png` at 256 and at 64 px, `title.png`, `dialogue-choice.png`, `hud-fight.png`. For each of the eight say who it is from the 64 px picture alone and what gives it away.
- [ ] **Step 6: Commit** — `feat: render the portraits from the dressed, faced figures`

---

### Task 4: Budget and the browser

**Files:**
- Modify: `e2e/look.spec.js` only if a frame it saves needs a new moment, `src/core/shader_warmup.gd` if a piece escapes it, `README.md`, this plan (Amendments)

- [ ] **Step 1: Measure:** triangles per dressed character (a test already limits it), `ops/build-web.sh` and `ops/build-web.sh public`, `ops/check-budget.sh` on both, `npx playwright test --trace off` (frame rate in the skirmish with six enemies and in the Fragua with five people; the Firefox title-to-Fragua times). Compare with milestone 4's numbers (60 fps; 50.3 MB; Firefox New-game-at-once about 12.7 s of 15).
- [ ] **Step 2: Fix what broke the budget,** re-measuring after each change. If the Firefox start grew, find the new shader variant and remove it.
- [ ] **Step 3: Look at the owner's frames** `build/e2e/look-*-chromium.png` and `-firefox.png`; describe each as someone seeing the game for the first time.
- [ ] **Step 4: Append "Amendments made while building" and "Carried forward"** to this plan.
- [ ] **Step 5: Commit** — `test:`/`fix:` per change, `docs: record milestone 5a's amendments`

---

### After the last task: put it online

Once the final review's fixes are in and the suites are green, the controller runs `ops/deploy-fly.sh`, checks that https://nocturne-of-ashes.fly.dev/ serves the new build and that a new game shows the dressed, faced figures, and reports the address with the frames.

---

## Amendments made while building

These decisions changed what the tasks above describe. The code follows the amendments.

- **Task 1.** Two terms in the tables of Tasks 1 and 2 were wrong and are corrected here: the crusader wears the helmet, and the sergeant the helmet over a coif, as the game already had them. The game was not changed.
- **Task 1.** The refactor that moved the gear's shared mesh code into `tools/blender/wearable.py` was accepted as leaving the gear unchanged on the evidence of its diff: it touches no asset, and across the task only the five cloth pieces changed, because their texture coordinates moved with the 16-square palette.
- **Task 2.** The 15,000-triangle cap for a dressed figure stayed. To fit under it the model lost the body every garment covers (chest, abdomen, upper arms), as Task 1 took off its head: the garments are the figure's surface there. A cap is a browser budget, not a formality.
- **Task 2.** The long skirts' ballooning in attack, run and sit was fixed in this task, though it came from the old cloth: once the figures were dressed it was the worst thing on them, and every fight showed it.
- **Task 5 (added).** A fifth task, "Nobody gets stuck, nothing drags", was added from a playability audit the owner asked for (no state was found that blocks progress) and done after Task 2 and before Task 3. Its nine items: a closing card when the story's vault is cleared, saying the story rests there and the game is saved; the second enemy group joins the fight; a notice when a vault left mid-fight has closed ranks again; Malakor clear of the party panels on the return from the vault; a line for each refusal that was silent; a title line when the browser will not keep saves; the world pauses itself when the page is hidden; Íñigo's second visit is a short reminder, not his whole speech; the title's preparing line counts its steps.
- **Task 5.** Fight difficulty and the length of the conversations were not changed, beyond making the second group join: they are design decisions, put to the owner with a recommendation.
- **Task 5.** On the web only a hidden page pauses the game; a window that merely loses focus does not. Private windows that keep storage until they close are not detected. The engine and the browsers give no signal for either, so the saves line misses those cases.
- **Task 5.** Once the second group is alerted every enemy has a target, so the vault's west door refuses for the rest of the fight: the mid-fight retreat the task's brief described is gone. A door was never usable while enemies attacked, a fall reloads at the vault's entry, and the fight is winnable; if the fight is made hard later, a retreat rule must be designed with it.
- **Task 3.** The review's items for the portraits (the face test's thin margin, the key light that burns white cloth, documenting the import step after rendering) were moved to the final fix wave, because Task 4 was editing the same files.
- **Task 4.** The owner's frames gained `look-closing` (the closing card on screen), and `look-lock` is now taken after the vault is cleared and the card closed, so it shows the last lock with the line that says where the story rests. The click and use helpers moved from the journey spec to `e2e/helpers.js`.

## Carried forward

- The fight is won in about 11 s by clicking the nearest enemy, with no Rite or feeding needed. Difficulty is the owner's pending decision, and a retreat rule must be designed with it, since the west door refuses once the second group is alerted.
- Six conversations make up about three quarters of a reading play, and Íñigo's first speech is pure rules. Trimming them is the owner's pending decision.
- A first play lasts 1.3–4 minutes against the design's 20–30: three of the slice's five story beats (the burning quarter, the escort, the last lock's boss) are not built, and the Cave of Hercules is one vault of its three or four encounters.
- Long skirts are boxy when seated and lumpy mid-fall, a raised knee can pass the skirt's cap, Malakor's mantle spreads into a dark bowl mid-fall and the smith's apron stays a board. Seen from the game camera, Álvar's habit reads as a white bell. In the fight the figures still bunch into one knot.
- White cloth and Malakor's lit cheek run hot in the portraits (queued for the final fix wave).
- On the web only a hidden page pauses the game; a window losing focus does not. Private windows that keep storage until closed cannot be detected, and the storage check runs at the title only.
- Firefox spends about 10.5 s preparing behind the title: four frames of 2.2–2.6 s each (a shader's two programs linked at once) among shorter ones, the same before and after this plan's heads and garments. New game pressed at once reaches the Fragua at about 13 s of the 15 s limit. Once the preparing is done, nothing compiles on first sight in either room.
- Conversations are not translated. In Spanish "Sangre" names both the Blood and the Sangre.
- Test gaps the reviews left: nothing checks that a garment's pieces float free of the body (the old check was dropped), the legs-in-skirts test has no ceiling on points beyond the cap, the cloth fit has no cost test, and the seam test's hull forgives centimetre gaps; the closing card's opening-frame key test is approximate, and the conversation test's tap is sensitive to timing under load.
- The floor texture's repeat shows, and the piers' faces on the camera side are near black.
- The camera cut pops at 60° of turn.
- The vault's west door is seen edge-on.
- Away from the return from the vault, the party panels or the dialogue box can still cover a character.
- Units can stand inside the people they talk to (`Npc`).
- `unit_visual.gd` (479 lines) is due for a split.
- `ops/bake-light.sh` has not been run end to end since its last edit.
- The texture path for GPUs without S3TC has never run on real hardware.
