# Nocturne of Ashes

A party-based Gothic action RPG for the web browser, built with Godot 4.7: a devout
medieval warrior turned against his will, a love that spans centuries, a forced sleep and
a waking in the present day. The first deliverable is a vertical slice set in medieval
Toledo that proves the core loop is fun: explore a hub, talk, feed, fight with a small
party, use blood powers and make choices that cost something.

Play the latest milestone in a desktop browser: https://nocturne-of-ashes.fly.dev/

Credits: [`CREDITS.md`](CREDITS.md), served beside the game as https://nocturne-of-ashes.fly.dev/credits.txt,
with the licence texts it names, the engine's included, in https://nocturne-of-ashes.fly.dev/licenses.txt.

Run the tests: `ops/test.sh`

Build for the browser: `ops/build-web.sh` (the test flavour, into `build/web`) or
`ops/build-web.sh public` (the public flavour, into `build/public`). The two come from the same source
and differ in one thing: the public one is exported with the `public` feature (the "Web public" export
preset), and there the [test parameters](#test-parameters), `probe=1` among them, do nothing. The site
runs the public flavour; the browser tests use the test flavour. Each build holds a `flavour.txt`
naming its flavour, and `tests/core/test_export_presets.gd` keeps the two presets alike.

Browser tests: `npx playwright test` (after `npm install` and the browser builds). Every test runs
against `build/web` but `e2e/public.spec.js`, which runs in Chromium against `build/public` and checks
that a `?probe=1&fresh=1` link leaves a visitor's save and title as they are. Without a public build
(no `build/public/index.html`) that test is left out and its server is not started; the rest run.

The Chromium run opens a browser window, because headless Chromium renders WebGL in software and cannot hold the frame rate.

Check the browser build's budget: `ops/check-budget.sh` (after a browser build), or
`ops/check-budget.sh build/public` for the public flavour. It fails when the build
is over 80 MB or a file other than the engine's `.wasm` is over 30 MB, and lists the ten largest assets
in the pack. `e2e/look.spec.js` holds the frame rate (30 a second with everyone in view) and the first
load (the title answering in under 20 s), New game pressed at once (the Fragua within 15 s), and saves the frames to show of each browser's run as `build/e2e/look-*.png`.
What the game never loads (unused kit pieces, the npm files) is left out by the export preset's exclude
filter. While the title is up, the rooms' shaders are compiled behind it a few at a time
(`ShaderWarmup`), with "Preparing the cellars…" showing; the title keeps answering between steps. In
Firefox this takes about ten seconds, in steps of up to about two and a half; a game begun once it is
done starts at once, one begun earlier waits for what is left on its first frame.

- Design: [docs/superpowers/specs/2026-11-15-vertical-slice-design.md](docs/superpowers/specs/2026-11-15-vertical-slice-design.md); the characters' faces and clothes: [docs/superpowers/specs/2026-11-21-character-art-design.md](docs/superpowers/specs/2026-11-21-character-art-design.md)
- Plans: [docs/superpowers/plans/2026-11-15-milestone-1-first-room.md](docs/superpowers/plans/2026-11-15-milestone-1-first-room.md), [docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md](docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md), [docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md](docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md), [docs/superpowers/plans/2026-11-16-milestone-4-toledos-look.md](docs/superpowers/plans/2026-11-16-milestone-4-toledos-look.md), [docs/superpowers/plans/2026-11-21-milestone-5a-faces-and-clothes.md](docs/superpowers/plans/2026-11-21-milestone-5a-faces-and-clothes.md)

## Making the art

Every character is one human model, `assets/characters/human/human.glb`, wearing a head and
garments of its own and coloured by a 16 × 1 pixel palette image (`palette-<name>.png`, squares left
to right: skin, hair, tunic, sleeves, skirt, hose, boots, trim for the body and clothes, then eye
white, iris, brow, lips, beard, socket, shade and stubble for the face). The model has no head and no
body under the clothes (chest, abdomen, upper arms): the head and the garments are its surface there.
`tools/make_character.py` makes the model and the palettes from
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
The heads are made the same way by `tools/blender/heads.py` (`assets/gear/head_<name>.glb`: faceted,
painted flat, hair and beards in geometry) and the garments by `tools/blender/garments.py` (habits,
robes, tunics and surcoats in rigid pieces per bone: chest, abdomen, sleeves, cuffs);
`tools/blender/wearable.py` holds what the three share. Each face of a head or garment points at its
square of the wearer's palette, so every figure is drawn with the body's one material. Their
docstrings have the commands and tables. To look at the figures, `tools/lineup.gd` (it needs a window)
draws the dressed eight in any clip, view and framing, or the game camera in a fight, into
`build/shots/`; its header has the arguments.

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
`godot --path . -s tools/render_portraits.gd` (it needs a window): each character's head and
shoulders, faced and clothed as in the game, in a three-quarter view under one warm side light, with
what it holds in its hands left out of frame; the title's Álvar is the same picture drawn larger. The interface's typefaces and
panel frames (`assets/ui/`) are made by `tools/make_ui.py`; its docstring has the command. Both write
the same bytes on every run. These small interface images keep Godot's lossless 2D import: they are
drawn at or near their own size in the interface, where block compression would smear the thin
frame edges and the faces, and together they add only a few hundred kilobytes to the build.

## Story so far

Brother Álvar wakes after his Turning in the Fragua, the forge-house of the Blood-Forged under Toledo,
and Malakor, its master, speaks to him first. In the Fragua he can talk with Malakor, with Íñigo the
smith, with a captive crusader in his alcove, and with Zahra and Gonzalo, who join the party. Two
choices move his Alma: what he does with the captive, and what he tells Malakor about the
letter he carried. Once Malakor gives the order, the stair opens onto the vault below, where the
crusaders wait; its last lock does not open yet. This is where the story rests for now: once the vault
is cleared, a card says so, once, and that the game and its Alma are kept for when the story goes on.

## Controls

- Left click on the floor to move the selected party member, on an enemy to attack it.
- Left click on a weakened enemy to feed on it; a red mark shows an enemy weak enough to feed on. Each group of crusaders has a tougher sergeant.
- Left click on a companion, or press Tab, to select another party member.
- 1 and 2 use the selected member's Rites; a Rite that needs a target waits for a click on one.
- Escape (or a right click) cancels a Rite's targeting.
- Space pauses and resumes the world; orders given while paused begin on resume. The world also pauses
  itself when the page is hidden (another tab, a minimised window), and waits for Space.
- Q and E turn the camera; the mouse wheel zooms.
- Left click on someone to have Álvar walk up and talk with them, whoever is selected; Enter, Space or a click on the box goes on, and 1–4 (or a click) take a choice.
- Left click on a door to have Álvar take the party through it, whoever is selected; a door stays shut while a fight is on or until the story opens it.
- Entering a room with no enemies left, such as the Fragua, restores the party's health; Blood is not restored.
- Enter, after Álvar falls, plays on from the last checkpoint.

Progress is saved in the browser: on entering a room, at the end of each conversation and when a room
is cleared. The title offers Continue when there is a save, and New game. When the browser will not keep
saves (its site data blocked, or a save that does not read back), the title says progress lasts only
until the page is closed; a private window that keeps data until it closes cannot be told apart.

## Test parameters

The browser tests start the game with query parameters in the page address (for example
`/?probe=1&fresh=1`). They exist for those tests; players need none of them. They work only in the
test flavour (`build/web`): in the public flavour, the one the site runs, `probe=1` and the
parameters that need it do nothing, and the game starts as for any visitor (`src/core/probe_gate.gd`).
`skirmish=1` and `lang=es` are not test parameters and work in both.

- `probe=1` — lets the tests read the game, and skips the title: Continue when there is a save, else New game.
- `title=1` — with `probe=1`: shows the title anyway.
- `fresh=1` — with `probe=1`: clears the save first; ignored without it.
- `calm=1` — with `probe=1`: the enemies stand still.
- `frail=1` — with `probe=1`: Álvar's health is set to 1 when a room with enemies starts.
- `at=vault` — with `probe=1` and `fresh=1`: starts in the vault as if the Fragua were finished.
- `skirmish=1` — plays the vault skirmish with the whole party, with no title and no save.
- `lang=es` — shows the game in Spanish.

Deploy to Fly.io (needs the fly CLI, logged in): `ops/deploy-fly.sh`. It builds the public flavour
into `build/public`, the only directory the image is made from, and stops before deploying unless
`ops/check-public-build.sh` finds that build to be the public flavour (its `flavour.txt` and the
feature in its pack).
