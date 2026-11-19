# Nocturne of Ashes

A party-based Gothic action RPG for the web browser, built with Godot 4.7: a devout
medieval warrior turned against his will, a love that spans centuries, a forced sleep and
a waking in the present day. The first deliverable is a vertical slice set in medieval
Toledo that proves the core loop is fun: explore a hub, talk, feed, fight with a small
party, use blood powers and make choices that cost something.

Play the latest milestone in a desktop browser: https://nocturne-of-ashes.fly.dev/

Run the tests: `ops/test.sh`

Build for the browser: `ops/build-web.sh`

Browser tests: `npx playwright test` (after `npm install` and a browser build)

The Chromium run opens a browser window, because headless Chromium renders WebGL in software and cannot hold the frame rate.

Check the browser build's budget: `ops/check-budget.sh` (after a browser build). It fails when `build/web`
is over 80 MB or a file other than the engine's `.wasm` is over 30 MB, and lists the ten largest assets
in the pack. `e2e/look.spec.js` holds the frame rate (30 a second with everyone in view) and the first
load (under 20 s), and saves the frames to show of each browser's run as `build/e2e/look-*.png`.

- Design: [docs/superpowers/specs/2026-11-15-vertical-slice-design.md](docs/superpowers/specs/2026-11-15-vertical-slice-design.md)
- Plans: [docs/superpowers/plans/2026-11-15-milestone-1-first-room.md](docs/superpowers/plans/2026-11-15-milestone-1-first-room.md), [docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md](docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md), [docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md](docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md)

## Making the art

Every character is one human model, `assets/characters/human/human.glb`, coloured by an 8 × 1
pixel palette image (`palette-<name>.png`, squares left to right: skin, hair, tunic, sleeves,
skirt, hose, boots, trim). `tools/make_character.py` makes the model and the palettes from
Quaternius's Universal Animation Library (CC0), which is not kept in the repository:

1. Download the standard edition from https://quaternius.com/packs/universalanimationlibrary.html
   (or https://opengameart.org/content/universal-animation-library) and unpack it outside the
   project's tracked files.
2. Run, from the repository root, with the path to its Godot file:
   `uv run --python 3.12 --with pygltflib==1.16.5 --with numpy==2.5.5 --with pillow==13.0.0 python3 tools/make_character.py "<unpacked>/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb"`
3. A palette change needs no library: edit `PALETTES` in the tool and run the same command with
   `--palettes-only` in place of the path.

The tool writes the same bytes on every run, so an unchanged input leaves `git status` clean. That
holds for the pinned library versions above: other versions of pygltflib, Pillow or zlib can write
the same model and palettes with different bytes, so keep the pins when running it.

The gear and cloth hung on the model (swords, shields, helmets, skirts, mantles, veils...) are made
by `tools/blender/gear.py`, one `assets/gear/<piece>.glb` each, plus `assets/gear/palette-gear.png`
for the colours of steel, wood and leather. Run it from the repository root with Blender 5.3 (it
refuses other versions, whose exporter may write other bytes):
`blender -b --factory-startup -P tools/blender/gear.py`. Its docstring has the table of which bone
each piece hangs from; `resources/gear/<piece>.tres` holds the same for the game, and each
character's `resources/dress/<name>.tres` lists what it wears. It too writes the same bytes on every run.

The rooms are built from a stone kit made by `tools/blender/kit.py`, one `assets/kit/<piece>.glb`
each: floor slabs, stone and brick walls, a pier, horseshoe and round arch bays, a barrel vault, a
door and its frame, a stair going down, the forge, props, a grille, a sconce and the sealed lock.
Run it the same way: `blender -b --factory-startup -P tools/blender/kit.py`; it writes the same bytes
on every run. Its docstring has the table of pieces: footprint on the 2 m grid, what each blocks and
on which physics layer. The pieces carry no textures: each face names one of five shared materials
(`resources/materials/stone|brick|plaster|wood|iron.tres`), and `tools/kit_import.gd`, the pieces'
import script, swaps those names for the materials and puts the collision bodies on their layers. The
materials' tiling textures, colour maps at 1024 px and normal maps at 512 px, are CC0 sets from Poly
Haven in `assets/textures/` (see `CREDITS.md`), imported with mipmaps.

The portraits (`assets/portraits/`) are rendered from the dressed figures by
`godot --path . -s tools/render_portraits.gd` (it needs a window). The interface's typefaces and
panel frames (`assets/ui/`) are made by `tools/make_ui.py`; its docstring has the command. Both write
the same bytes on every run. These small interface images keep Godot's lossless 2D import: they are
drawn at or near their own size in the interface, where block compression would smear the thin
frame edges and the faces, and together they add only a few hundred kilobytes to the build.

## Story so far

Brother Álvar wakes after his Turning in the forge-haven of the Blood-Forged, under Toledo, and
Malakor, its master, speaks to him first. In the haven he can talk with Malakor, with Íñigo the
smith, with a captive crusader in his alcove, and with Zahra and Gonzalo, who join the party. Two
choices move his Conscience: what he does with the captive, and what he tells Malakor about the
letter he carried. Once Malakor gives the order, the stair opens onto the vault below, where the
crusaders wait; its last lock does not open yet.

## Controls

- Left click on the floor to move the selected party member, on an enemy to attack it.
- Left click on a weakened enemy to feed on it; a red mark shows an enemy weak enough to feed on. Each group of crusaders has a tougher sergeant.
- Left click on a companion, or press Tab, to select another party member.
- 1 and 2 use the selected member's Gifts; a Gift that needs a target waits for a click on one.
- Escape (or a right click) cancels a Gift's targeting.
- Space pauses and resumes the world; orders given while paused begin on resume.
- Q and E turn the camera; the mouse wheel zooms.
- Left click on someone to have Álvar walk up and talk with them, whoever is selected; Enter, Space or a click on the box goes on, and 1–4 (or a click) take a choice.
- Left click on a door to have Álvar take the party through it, whoever is selected; a door stays shut while a fight is on or until the story opens it.
- Entering a room with no enemies left, such as the haven, restores the party's health; Blood is not restored.
- Enter, after Álvar falls, plays on from the last checkpoint.

Progress is saved in the browser: on entering a room, at the end of each conversation and when a room
is cleared. The title offers Continue when there is a save, and New game.

## Test parameters

The browser tests start the game with query parameters in the page address (for example
`/?probe=1&fresh=1`). They exist for those tests; players need none of them.

- `probe=1` — lets the tests read the game, and skips the title: Continue when there is a save, else New game.
- `title=1` — with `probe=1`: shows the title anyway.
- `fresh=1` — with `probe=1`: clears the save first; ignored without it.
- `calm=1` — with `probe=1`: the enemies stand still.
- `frail=1` — with `probe=1`: Álvar's health is set to 1 when a room with enemies starts.
- `at=vault` — with `probe=1` and `fresh=1`: starts in the vault as if the haven were finished.
- `skirmish=1` — plays the vault skirmish with the whole party, with no title and no save.
- `lang=es` — shows the game in Spanish.

Deploy to Fly.io (needs the fly CLI, logged in): `ops/deploy-fly.sh`
