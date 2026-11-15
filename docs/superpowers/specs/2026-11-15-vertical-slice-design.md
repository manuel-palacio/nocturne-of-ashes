# Nocturne of Ashes — vertical slice design

Date: 2026-11-15. Status: draft, awaiting approval.

Items marked **(call)** were decided by the designer's assistant and are open
to correction. Everything else was stated by the project owner.

## Intent

A spiritual successor to the 2000 party-based vampire action RPG
*Vampire: The Masquerade – Redemption*: a devout medieval warrior turned
against his will, a love that spans centuries, a forced sleep and a
waking in the present day. Original cast, factions, setting and
vocabulary; nothing copied from the original game or its setting.

The first deliverable is one **vertical slice**, playable in a web
browser, that proves the core loop is fun: explore a hub, talk, feed,
fight with a small party, use blood powers, make choices that cost
something.

## Goals

- Playable in a desktop browser from a URL, no install.
- About 20–30 minutes of play, start to finish **(call)**.
- Set in medieval Toledo.
- Party combat, blood powers, feeding and a conscience score all present
  in simple form.
- A Gothic night-time mood that holds up within browser rendering limits.

## Non-goals (this slice)

- The modern era, firearms, hacking, surveillance.
- Multiple endings (the slice ends on a cliffhanger; the three endings
  belong to the full game).
- Multiplayer or a storyteller mode.
- Phones and touch controls **(call)**.
- Voice acting **(call)**: text dialogue with portraits.
- Inventory depth: a handful of items (weapon, armour, blood vial), no
  shops or loot tables **(call)**.

## Anti-goals

- Any name, term, clan, character, line of text, sound or image taken
  from the original game or the World of Darkness setting.
- A build too heavy for the browser: over about 80 MB to download or
  under 30 fps on an ordinary laptop **(call on the numbers)**.

## Setting and story

### Toledo, summer 1212 **(call on the year)**

The owner asked for "ancient Toledo". The proposal is the summer of
1212: a crusading army from beyond the Pyrenees has gathered in Toledo
before marching south to Las Navas de Tolosa. The foreign crusaders
turn on the city itself and attack the Jewish quarter; knights of
Toledo take up arms to defend their neighbours. That gives the slice a
historical night of fire and street fighting, as the original pitch had
with the sack of Constantinople.

Toledo also supplies the rest of the story for free:

- **The School of Translators** — Christian, Jewish and Muslim scholars
  translating Arabic and Greek learning. Elena's workplace.
- **The Cave of Hercules** — real Roman vaults under the city, and the
  legend of a sealed house on which every king hung a new lock until
  King Roderic broke them and lost the kingdom. This is the vault where
  the ancient progenitor sleeps.
- **Toledo steel** — the swordsmiths' city; a natural home for the
  Blood-Forged.
- The city's medieval reputation as a school of forbidden arts.

### Cast **(names are calls except Elena and Malakor)**

- **Brother Álvar** — the hero. A knight-friar of the Order of
  Calatrava, devout, in Toledo with the royal host. Replaces "Vasilis",
  whose name belonged to Constantinople.
- **Elena** — a Mozarab translator at the School. She is smuggling
  manuscripts and a relic out of the burning quarter.
- **Malakor** — warlord of the **Blood-Forged**, a rebellious warrior
  bloodline. Turns Álvar to use him as a shock trooper. Wants the vault
  under the city opened.
- **Zahra** — companion. An Andalusi physician, turned decades ago;
  healer and blood-caster, sceptical of Malakor.
- **Gonzalo** — companion. An old Blood-Forged swordsmith; heavy
  fighter, loyal to the bloodline, torn when Álvar defies it.

### Our own vocabulary **(call)**

| Idea | Our term |
|---|---|
| Being made a vampire | the Turning |
| Vampire powers | Gifts |
| Morality score | Conscience |
| Centuries of sleep | the Long Sleep |
| Secrecy from mortals | the Veil |
| Hunger-driven loss of control | the Fury |

### The slice, beat by beat

1. **The burning quarter.** Álvar, mortal, fights through streets to
   reach the School. Teaches movement and combat. Alone.
2. **The escort.** He leads Elena toward the Tagus gate. Malakor
   ambushes them; Álvar falls; the Turning. Elena escapes with the relic.
3. **The forge-haven.** Álvar wakes in the Blood-Forged haven, a
   swordsmiths' cellar complex. Small hub: four or five characters to
   talk to, first feeding (a captive crusader: sip, drain, or refuse —
   the first Conscience choice), first Gifts, Zahra and Gonzalo join.
4. **The Cave of Hercules.** Malakor sends the three below to break the
   old locks. Dungeon of Roman vaults and flooded galleries, three or
   four combat encounters, one simple lock puzzle.
5. **The last lock.** Elena is there with the relic, sealing what the
   locks hold. Álvar chooses her over Malakor. Boss fight against
   Malakor's lieutenant **(call: not Malakor himself, who must survive
   for the full game)**. The vault collapses; Álvar is buried. Title
   card: the Long Sleep.

In the full game the present-day half moves to modern Toledo and Madrid
instead of Istanbul and London **(call; outside this slice)**.

## How it plays

- **Camera:** elevated third-person, rotatable and zoomable, following
  the selected character **(call)**.
- **Control:** click to move, click an enemy to attack, number keys for
  Gifts, Tab or portraits to switch character, Space to pause and give
  orders **(call)**. Companions fight on their own when not directed.
- **Stats:** Health, Blood, Conscience. No experience levels in the
  slice; Gifts unlock at story beats **(call)**.
- **Blood:** Gifts cost Blood. Blood is regained by feeding on a
  weakened enemy in combat or on mortals in the hub. At very low Blood
  the Fury takes over: the character attacks the nearest target for a
  few seconds.
- **Gifts (six, two per character) (call):**
  - Álvar — *Iron Sinew* (short burst of strength and speed),
    *Dread Gaze* (stuns one enemy).
  - Zahra — *Mend Flesh* (heal an ally), *Blood Lance* (ranged damage).
  - Gonzalo — *Stone Hide* (damage reduction, draws enemies),
    *Hammerfall* (area knock-down).
- **Conscience:** moves on about four choices in the slice (how he
  feeds, mercy to a wounded crusader, carrying out or quietly dodging
  an order from Malakor in the haven, a dying mortal in the cave). The
  final choice of Elena over Malakor is fixed story, not a branch. It changes some dialogue lines and the
  wording of the final scene. Its combat effects belong to the full game.
- **Death:** a fallen companion revives after the fight; if Álvar
  falls, reload from the last checkpoint **(call)**.
- **Saving:** automatic checkpoints at each beat, one save, kept in the
  browser.
- **Languages:** English and Spanish **(call)**.

## Approaches considered

| Approach | Trade-off |
|---|---|
| Unreal 5 + Blender | Highest visual ceiling; no supported browser export. Ruled out by the browser goal. |
| Unity 6 + Blender | Best 3D in the browser; new pipeline, heavier builds, licence terms, editor-centred workflow. |
| Three.js / Babylon.js + Blender | Web-native and light; no editor, so scenes, animation and UI tooling would be hand-built. |
| **Godot 4 + Blender (chosen)** | Browser export built in, direct Blender import, text-based project files. The owner already ships a Godot web game with tests and deployment, so the pipeline is proven. Cost: the browser renderer has no real-time global illumination. |

The owner asked for a recommendation and Godot was proposed and not
objected to.

## Technical constraints and calls

- **Godot 4.7** (the version the owner's other game uses), GDScript
  (C# does not export to the web in Godot 4), Compatibility renderer
  (WebGL 2).
- **Look:** stylised low-to-mid-poly 3D. Mood from baked lightmaps,
  torch and fire light, depth fog, colour grading and particles. No
  reliance on real-time global illumination or volumetric fog.
- **Art sources, in order of preference:** CC0 libraries (Quaternius,
  Kenney, Poly Haven, ambientCG) for characters, animations, props and
  textures; Blender Python scripts for Toledo-specific architecture
  (horseshoe arches, Roman vaults, the forge); hand modelling only where
  neither fits. Every third-party asset recorded in `CREDITS.md`.
- **Libraries over hand-written code:** Godot's navigation for
  pathfinding; a maintained dialogue add-on (Dialogue Manager) for
  conversations and choices; GUT for unit tests; Playwright for browser
  tests of the exported build. Godot has no off-the-shelf ability
  framework comparable to Unreal's, so Gifts use a small resource-based
  ability system written for this game.
- **Characters and portraits (call):** CC0 base characters and
  animation sets, re-dressed and re-textured in Blender by script so the
  cast is distinct. Portraits are Blender renders of those same models.
  No paid assets and no image-generator art.
- **Story moments (call):** staged in the engine with scripted camera
  moves, existing animations, dialogue boxes and fades. No bespoke
  cutscene animation; the Turning and the collapse lean on fades, sound
  and a still image.
- **Audio:** CC0 or CC-BY music and effects, credited.
- **Repository:** a new repository, `nocturne-of-ashes`, structured like
  the owner's existing Godot game (`src/`, `scenes/`, `assets/`,
  `tests/`, `tools/`, `ops/`).
- **Hosting:** a static web build behind a small web server, deployed
  the same way as the owner's existing game. Going public is a separate
  step that needs the owner's say-so.
- **Targets (call):** Chrome and Firefox on desktop are required;
  Safari is best effort. 60 fps aim on a laptop with integrated graphics
  from about 2020 (Apple M1 or Intel Iris Xe class); download under
  about 80 MB.
- **If the slice runs long, cut in this order (call):** Spanish, the
  lock puzzle, Safari, then merge beats 1 and 2 into one street scene.
  The haven, the cave, the party of three and the six Gifts are
  protected. No deadline has been set.

## Left to the builder

- Scene and code structure inside the conventions above.
- Enemy types and numbers per encounter, damage numbers and tuning.
- The exact lock puzzle.
- Dialogue wording, within the beats and the vocabulary table.
- UI layout: portraits with Health and Blood bars, Gift bar, dialogue
  box, pause indicator.
- Which specific CC0 packs to use.
- Build order, provided an early milestone puts one character walking
  and fighting in a lit room **in the browser**, so browser limits show
  up first rather than last.
