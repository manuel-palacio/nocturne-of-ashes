# Character art: faces and real clothes — design

Short design for the opening work of milestone 5. It answers the weakest point of milestone 4's
look: every figure is a smooth-faced mannequin with a bare, muscled torso, and the portraits and the
title show it most.

## Intent

People, not mannequins. A player should tell Álvar the friar from Gonzalo the smith by face, hair and
dress, in a 64 px portrait and at the game camera, and the title should show a friar, not a torso.

## Goals

- Each of the eight dressed characters (Álvar, Zahra, Gonzalo, Malakor, Íñigo the smith, the captive,
  the crusader, the sergeant) has a head with a face of its own: brow, nose, cheekbones, jaw, eyes,
  mouth, and hair, beard, tonsure, veil, coif or helmet as fits.
- Nobody shows the mannequin's bare muscled torso. Every body is covered by a garment with its own
  shape: Álvar a habit with scapular and a cowl lying on the shoulders; Zahra a robe and veil;
  Malakor a long dark robe; Gonzalo and Íñigo tunic and leather apron; the captive a torn shirt; the
  soldiers a surcoat over mail with a coif, the sergeant a nasal helmet.
- The portraits and the title are rendered again from the new figures, head and shoulders, and read
  as people.
- Everything keeps working as it does: the 13 clips, cloth that bends, marks, the Fury tint, the
  faint lift in the dark, the read-only rule (visuals never write gameplay state).

## Non-goals

- Facial animation, lip movement, blinking.
- New animation clips, new characters, new gameplay.
- Elena (she does not appear before a later milestone).
- Fixing how melee reads as a knot; clothes that fit closer may help, and it is judged afterwards.

## Anti-goals

- Realistic faces on low-polygon bodies. The look stays faceted and painted flat, like the rooms'
  figures now; a face is planes and a few painted features, closer to a carved saint than a photo.
- Anything from an image generator, a paid pack, or the original game's look.

## Constraints

- A character stays under 15,000 triangles; the web build under 80 MB; 60 frames a second holds; no
  new shader variants (the Firefox start is already paid for in seconds per variant).
- Tools are deterministic and pinned, like `tools/make_character.py` and `tools/blender/gear.py`;
  outputs are committed; nothing downloaded is needed.
- Existing saves keep loading; the portraits' file names and the speaker table stay.

## Approaches

1. **Sculpt onto the current model (chosen).** Heads and garments are made in Blender by script and
   worn by the mannequin that is already animated. Keeps all clips and the cloth system, improves
   figures and portraits together, and every asset is ours. Most work per character.
2. **Swap the base model** for a CC0 set that already has faces and medieval clothes. Faster if one
   fits, but the available sets are cartoonish, the clips need retargeting and the cloth work is
   partly redone.
3. **Painted 2D portraits only.** Cheapest fix for the title and dialogue, but the figures in play
   stay faceless and it needs an artist; generated images are ruled out.

The owner chose the first on 2026-11-21.

## The how, as decided

- **Heads** are a new kind of gear piece, built by a Blender script from a small table per character
  (skull width, jaw, brow, nose, cheek, age; hair or tonsure or bald; beard; headwear). A head is
  skinned to the head and neck bones and replaces the mannequin's head, which is no longer drawn
  under it. Eyes, brows and mouth are painted: extra regions in each character's palette, not
  geometry.
- **Garments** are shells over the torso, arms and hips that take their bone weights from the
  mannequin, so they follow every clip. Where a garment hangs (habit skirt, robe, cowl, veil) it
  uses the existing shape tables and cloth fit. The body under a garment is not drawn.
- **The dress resource** names a head and garments as it names gear today; the game, the portrait
  tool and the title all build figures through the one path they share now.
- **Portraits** go back to head and shoulders, lit from one side, 256 px, plus the 512 px title
  render.

## Left to the builder

- The exact shape tables per character, within the descriptions above and judged by looking: a
  line-up frame of all eight, a 64 px portrait sheet, and frames in both rooms, in the dark corner
  and mid-fight.
- How many triangles a head and a garment get inside the budget.
- Whether hands and feet stay the mannequin's (expected: yes, recoloured).

## Done when

The eight can be told apart in a 64 px portrait sheet and at the game camera; no bare torso or
blank face is visible anywhere in play, on the title or in a portrait; all tests pass and the
browser budget holds.
