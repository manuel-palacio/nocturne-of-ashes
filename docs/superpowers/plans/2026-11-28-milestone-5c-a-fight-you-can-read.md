# Milestone 5c: A Fight You Can Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the crush of the vault a player can see at a glance who is a sergeant, how hurt each fighter is, who can be drunk from, what the pointer is on, and which companion is in trouble; and the guard that tires loses its bite as well as its health.

**Architecture:** Reading aids are drawn in the interface layer (2D controls placed from the units' screen positions), not in the 3D scene, so they add no shader to compile and never hide behind a figure. They read units and never write them. One small rule changes in the fight (the tiring guard), measured by the scripted players already in the suite.

**Tech Stack:** Godot 4.7.2, GDScript, GUT, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md`. Why now: the final review of milestone 5b could not tell sergeants from crusaders in the crush and mis-clicked a feed by sight (`docs/superpowers/plans/2026-11-24-milestone-5b-a-fight-that-matters.md`, "Carried forward").

## Global Constraints

- Godot **4.7**, GDScript only, `gl_compatibility`, web export. Typed GDScript, tabs, one class per file with `class_name`.
- **No new shader variant** and nothing new in the 3D scene for the reading aids: 2D controls only. The Firefox start (about 13 s of a 15 s bar) must not get longer; frame rate in the six-enemy fight stays at the browser tests' bar (aim 60).
- **Reading aids read, never write:** no aid changes a unit's state, an order, or what a click does. Clicks pass through every aid (mouse filter ignore) exactly as before.
- **Nobody gets stuck:** every row of `tests/story/test_fight_balance.gd` keeps holding; rows whose numbers this plan changes on purpose are re-measured over two ten-run passes and their bars re-set by the file's own rule.
- Every player-readable string is translated (Spanish in `assets/i18n/es.po`; the coverage test passes). Terms: the Blood / la Sangre, Rites / Ritos, the Fury / la Furia.
- Saves from the published build keep loading. Nothing takes keyboard focus. No `SceneTree.paused`.
- Commits: Conventional Commits with the types feat, fix, test, docs, refactor, chore, ci only; subject 72 characters or fewer; one logical change each; authored as `Manuel <emanuel.palacio@gmail.com>`; ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- Every task ends with `ops/test.sh` passing in full.

## Review Focus

1. **Told apart in the crush:** with six enemies and three party members within two metres of each other at the default camera, a person looking at a still frame can point to each sergeant, say who is most hurt on each side, and say who can be fed on. Judged from frames, at 1280 × 720 and 800 × 500.
2. **The pointer tells the truth:** what the hover label names is what a click would act on (the same pick the click uses), including when figures overlap, and it says what the click would do (attack, feed, talk, use).
3. **Aids never get in the way:** they do not cover the party panels, the Rite bar, hints, notices, the dialogue box or the cards; they are hidden in conversations and on the cards; they do not catch clicks; they follow the camera's turns and zoom without lag or jitter.
4. **Cost:** with nine fighters the aids cost under half a millisecond a frame and no per-frame allocation that grows.
5. **The tiring guard still frees the weakest player, sooner and without turning to paper.**

---

### Task 1: Read the fight

**Files (expected):** `src/ui/fight_marks.gd` (new, one overlay control owned by the HUD), `scenes/ui/hud.tscn`, `src/ui/hud.gd`, `src/ui/party_member_panel.gd`, `src/player/player_input.gd` (only to expose the pick it already makes, not to change it), `src/units/unit.gd` or stats only if a display name or rank is missing, `resources/dress/sergeant.tres` and `tools/blender/gear.py` + `assets/gear/` if the sergeant gets a crest, `assets/i18n/es.po`, `tests/ui/test_fight_marks.gd` (new), `e2e/look.spec.js`.

**What is drawn, in the interface layer, placed each frame from the units' positions through the camera:**
1. **A health bar over every fighter in a room with a fight on** (enemies and party): about 44 × 5 px at the default zoom, 10 px above the head, red for enemies and the party's own red for members, a thin dark frame; scaled gently with zoom and clamped (never under 28 px or over 64 px wide). A unit at full health that nobody has struck shows no bar; a fallen unit shows none. Overlapping bars are nudged apart vertically so each can be read.
2. **A sergeant reads as a sergeant.** His bar is wider (1.4×) with a small chevron at its left end, and his name shows over it while the pointer is near or while he is stilled. If, after that, a still frame of the crush still does not show which two are the sergeants, give the sergeant a crest on his helmet (a rigid gear piece in the tool's style, under 120 triangles, the body's kind of material) and say so.
3. **Who can be drunk from.** The existing white drop mark is hard to see in a crowd: draw the drop in the interface layer too, beside that enemy's bar, larger (16 px), and pulse it gently when the selected member is short of Blood or health (when a click would feed). The 3D drop stays or goes: decide by looking, and say.
4. **Who is being drunk from, stilled, or in the Fury:** a small word under the bar (the same words the party panels use: Feeding, Stilled, The Fury; an enemy being fed on shows a drop that drains), translated.
5. **What the pointer is on.** A label by the pointer naming what a click would act on and what it would do: "Sergeant — attack", "Crusader — feed", "Zahra — select", "Íñigo — talk", "The stair — use", with the Rite's name when a Rite is waiting for its target ("Baleful Eye → Sergeant"). It uses the very pick the click uses (`PlayerInput`'s own picking, exposed as a read-only query), so label and click cannot disagree. The figure under the pointer gets a ring at its feet in the interface layer (an ellipse outline), so the player sees which figure of an overlapping pair is meant. Nothing when the pointer is over the HUD.
6. **A companion in trouble.** A party panel pulses its frame when its member is under a third of health in a fight, and shows a small drop when that member is short of Blood (under a third). Clicking the panel selects as now.

**Not drawn:** numbers, enemy Blood, buffs lists, damage floaters, a minimap.

- [ ] **Step 1: Write the failing tests** (`tests/ui/test_fight_marks.gd`): a bar appears over a struck enemy at the right screen place (within 6 px of the projected head point plus the offset) and follows a camera turn within one frame; none over an unstruck full-health unit, a fallen unit, or outside a fight; a sergeant's bar is 1.4× a crusader's and carries the chevron; bars of two units at the same screen point are both fully visible (their rects do not intersect); the interface drop shows exactly when the unit has its feed mark and pulses exactly when `click_at` on it would feed; the hover label names the unit that `click_at` at that point acts on and the action it takes, for: an enemy (attack), a marked enemy with the selected member short of Blood (feed), a companion (select), a talkable person (talk), a door (use), a Rite waiting for a target (the Rite's name), two overlapping enemies (the one the click picks), and nothing over a HUD panel; every aid has mouse filter ignore and a click through a bar orders what it ordered before; aids are hidden while a conversation, a card or the title is up and in a room with no fight (except the hover label for people and doors); a panel pulses under a third of health in a fight and not otherwise; Spanish for every new word; with nine fighters, 600 frames of the overlay cost under 0.5 ms a frame on this machine (measured in the test and printed; the assertion is generous, 1 ms).
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Build it.**
- [ ] **Step 4: Full suite; both builds; the browser tests (the fight's frame rate; add `look-crush` to the owner's frames: mid-fight with all nine close together).**
- [ ] **Step 5: Look at it.** Frames at 1280 × 720 and 800 × 500, English and one in Spanish (`build/shots/read-*.png`): the crush with both sergeants in it; a marked enemy with the selected member short of Blood; the pointer on a sergeant, on a marked crusader, on one of two overlapping enemies, on a companion, on Íñigo, on the stair; a Rite waiting for its target; a companion in trouble; the Fury. For the crush frame answer the three questions of Review Focus 1 from the frame alone, and say what is still hard to see.
- [ ] **Step 6: Commit** — `feat: draw health over the fighters`, `feat: mark the sergeants and the foes one can drink from`, `feat: name what the pointer is on and what a click would do`, `feat: show on its panel a companion in trouble`

---

### Task 2: The guard tires in its arm as well

**Files (expected):** `src/main.gd` (the tiring), the enemy units' damage where the guard's strength is applied, `tests/story/test_tiring_guard.gd`, `tests/story/test_fight_balance.gd` (rows H and I and the header), `assets/i18n/es.po` only if a text changes, this plan (its closing sections), `README.md`.

**The rule.** A tired guard strikes more weakly as well as having less health: at each step both are scaled by the same share. With that, the floor rises: find the highest floor (in steps of 5%) at which the spam clicker at the floor still clears at least 9 of 10 with Blood (row H) and at least 9 of 10 from a dry start (row I), over two ten-run passes, and the steepest sensible step (15% or 20% a fall) so that an ordinary spam clicker is very likely through by his fourth fall and a dry one by his fifth. The aim is a floor of 40% or higher; report the table for each candidate. Nothing else in the fight changes; rows A–G are re-run once to show they did not move (the tiring does not apply to a first attempt).

- [ ] **Step 1: Write the failing test** (a tired guard's blows are scaled as its health is, at each step; the first attempt is untouched; the count's lifetime is unchanged).
- [ ] **Step 2: Fail, implement, measure the candidates, set the floor and step, re-set rows H and I by the file's rule (one win looser than the worse of two passes), update the header.**
- [ ] **Step 3: Full suite; browser tests.**
- [ ] **Step 4: Replay in the browser at a person's pace** a spam clicker with Blood and one dry, with the new reading aids on, and report falls and minutes to get through, and how the last fight looked (a fight, or paper).
- [ ] **Step 5: Append "Amendments made while building" and "Carried forward" to this plan; update the README's paragraph on the fight.**
- [ ] **Step 6: Commit** — `feat: tire the guard's arm as well as its health`, `test: hold the tired guard's floor to what two passes measured`, `docs: record milestone 5c`

---

### After the last task: put it online

Once the final review's fixes are in and the suites are green, the controller runs `ops/deploy-fly.sh`, checks the live site (a fight shows health over heads and the hover label, in English and Spanish), and reports with the frames.
