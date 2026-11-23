# Milestone 5b: A Fight That Matters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The vault fight needs the things the game is about (Rites, feeding, the pause, a way out), and the rules are taught in the vault when they first apply instead of in a speech.

**Architecture:** Numbers, one new door rule, a handful of one-time hints through the existing notice mechanism, and a shorter speech. No new systems. The fight is tuned against scripted players run headless, kept as tests, so "plain clicking loses, playing with the Blood wins" is measured and stays true.

**Tech Stack:** Godot 4.7.2, GDScript, GUT, Playwright.

**Spec:** `docs/superpowers/specs/2026-11-15-vertical-slice-design.md` ("proves the core loop is fun: feed, fight with a small party, use blood powers"). Decided by the owner on 2026-11-24, from the playability audit recorded in `docs/superpowers/plans/2026-11-21-milestone-5a-faces-and-clothes.md` ("Carried forward"): make feeding and Rites matter in the fight, with a retreat rule; cut Íñigo's rules speech and teach feeding and the Fury in the vault.

## Global Constraints

- Godot **4.7**, GDScript only, `gl_compatibility`, web export. Typed GDScript, tabs, one class per file with `class_name`.
- The game's terms: the Blood, Rites, Alma, the Silence, the Fragua, the Sangre, the Fury. Nothing from the original game or its setting.
- **Nobody gets stuck.** No checkpoint may capture a state that cannot be won; a fall always leads back to a fight that can be won; the story's gates are untouched. The tests in `tests/story/test_playability.gd` keep passing; those that pin a number or rule this plan changes on purpose change with it and are named in the report.
- Every player-readable string outside conversations is translated (Spanish in `assets/i18n/es.po`); conversations stay English until they are translated as a whole.
- Saves from the published build keep loading (`VERSION` stays 1; new flags are optional).
- Holding the world never uses `SceneTree.paused`. Nothing takes keyboard focus.
- Commits: Conventional Commits with the types feat, fix, test, docs, refactor, chore, ci only; subject 72 characters or fewer; one logical change each; authored as `Manuel <emanuel.palacio@gmail.com>`; ending with `Co-Authored-By: Claude <noreply@anthropic.com>`. No absolute paths, hostnames or machine details in any file or message. Never `--no-verify`.
- The browser budget holds: build under 80 MB, the browser tests' frame-rate assertions pass.
- Every task ends with `ops/test.sh` passing in full, clean output, no orphans.

## Review Focus

1. **Plain clicking no longer wins, and playing properly does.** Measured by scripted players over varied runs, kept as tests.
2. **No unwinnable state:** entering the vault with no Blood, after draining the captive or sparing him, after spending Blood on Rites in the Fragua; falling repeatedly; leaving and returning.
3. **The hints teach and then get out of the way:** each shows once, at the moment it applies, never over a conversation or a card, never twice after a reload, and none is needed to finish.
4. **The fight still reads:** six enemies at once with tougher numbers must not turn into a slog (a won fight in roughly 45–90 seconds) or an instant fall.
5. **The first minutes are not harder to understand** with a shorter speech: a first-time player still learns what Blood, Rites, feeding, the Fury and the Silence are before or as they need them.

---

### Task 1: The fight needs the Blood

**Files (expected):** enemy and party stats (`resources/` and the unit scenes that hold them), `scenes/rooms/vault_room.tscn`, `src/rooms/encounter.gd`, `src/rooms/travel.gd`, `src/units/combat_brain.gd` only if a brain rule must change, `src/main.gd`, `src/ui/hud.gd`, `assets/i18n/es.po`, `tests/story/test_fight_balance.gd` (new), `tests/story/test_playability.gd`, `e2e/*.spec.js` that fight for real.

**The scripted players** (in the test file, driving the real story vault with brains on, through the same entry points a player's clicks use):
- *Clicker*: Álvar attacks the nearest living enemy, again when it dies. No Rites, no feeding, no pause.
- *Player*: as the clicker, and: uses Iron Sinew when a fight starts and whenever it is off and he can pay; uses Baleful Eye on a sergeant when he can pay; feeds on a marked enemy whenever his Blood is under half; orders a companion to feed when theirs is under a third.
- *Coward*: when Álvar's health is under a third he walks to the west door and uses it.
Each run varies (start positions jittered within a metre, the random seed set per run) so ten runs are ten fights, and every run is bounded in game time.

**Targets** (tune the numbers until they hold; report the table):
| start | scripted player | must |
|---|---|---|
| as a new game arrives (the captive spared: least Blood) | Clicker | fall in at least 7 of 10 |
| the same | Player | clear in at least 8 of 10, in 45–90 s of game time |
| the captive drained (most Blood) | Player | clear in at least 9 of 10 |
| every party member at 0 Blood | Player | clear in at least 6 of 10 (the Fury may happen; feeding must be able to dig them out) |
| any | Coward | reaches the Fragua in at least 8 of 10 once he turns |

**How to get there** (the levers, in order of preference): enemies' health and damage, the sergeants' especially; what feeding gives and how long it takes; the costs and strengths of Iron Sinew and Baleful Eye; the party's starting Blood on first entering the vault if the story's own numbers leave too much (the party should arrive with about half). Leave the party's health, movement and the brains' rules alone unless a target cannot be met without them, and say so.

**The way out.** The west door answers "Not while they are upon you" only while an enemy is within 3 m of Álvar; otherwise it lets the party through, mid-fight included. The Fragua heals as it does now, the vault's guard is whole again on return, and the existing notice says so. A fall is unchanged.

**The third fall.** From the third fall in the same room onward, each fall leaves the enemies there with 10% less health than the last time, down to 70% of their tuned health; a notice on re-entry says the guard is tiring ("The guard is tiring."). It resets when the room is cleared or left. This is the floor under Review Focus 2: nobody is walled in by the tuning.

- [ ] **Step 1: Write the scripted players and the target table as tests; run them against the game as it is; record the numbers (the Clicker clears 10 of 10 today).**
- [ ] **Step 2: Tune until every target holds; keep a record of each change and what it moved.**
- [ ] **Step 3: The door rule and the tiring guard, each with its tests** (door refused with an enemy at 2 m, allowed at 4 m mid-fight; the Coward test; third and fourth falls lower enemy health by the stated steps and no further than 70%; the count resets on clearing and on leaving).
- [ ] **Step 4: The existing playability and browser tests:** change only what pins the old numbers or the old door rule; `e2e/journey.spec.js` and others that fight for real must still win (they may play as the Player does, or keep `calm=1` where they used it).
- [ ] **Step 5: Play it** in the built game by script at human pace as Clicker and as Player; capture `build/shots/fight-*.png` at the start, mid-fight with a feed, a Fury, the fall prompt, the door mid-fight. Say how it feels: slog, coin-flip or fight.
- [ ] **Step 6: Commit** — `test: script a clicker, a player and a coward for the vault`, `feat: make the vault's guard a fight for the Blood`, `feat: let the party break away through the west door`, `feat: tire the guard after a third fall`

---

### Task 2: The rules are taught where they apply

**Files (expected):** `dialogue/haven.dialogue`, `src/main.gd` or a small `Hints` node beside `Travel` and `Conversation`, `src/ui/hud.gd`, `src/core/game_state.gd` only if hint flags need a helper, `assets/i18n/es.po`, `tests/story/test_hints.gd` (new), `tests/story/test_haven.gd`, `tests/story/test_playability.gd`.

**Íñigo's first speech becomes three lines** (his opening line still changes once the captive is seen to; his short second visit stays):

```
Íñigo: Stand there, out of the sparks. He told me to tell you how things are, and I have iron cooling.
Íñigo: The Blood in you is not your own now. Every Rite spends it. When it runs low you drink; let it run dry, and the Fury drinks for you.
Íñigo: And the Silence: the living above must never learn what walks beneath them. That is all. Hand me the tongs on your way out.
```

**Hints** are one-time notices (the existing notice mechanism, longer on screen than a door's line: 6 s, or until the next hint), each remembered in the save so it never shows twice, none shown while a conversation, a card or the fall prompt is up (a hint that falls due then waits for the moment to pass or is dropped if it no longer applies), all translated:

| when it first happens | hint |
|---|---|
| the party first enters the vault with enemies in it | "Space pauses the fight: give your orders, then let it run." |
| a Rite is first affordable in a fight and none has been used yet, 4 s in | "1 and 2 call your Rites. Each spends Blood." |
| an enemy first becomes feedable | "A weakened foe is marked. Click them to feed and take back Blood." |
| a party member's Blood first falls under a third | "%s is running dry. Feed, or the Fury will choose for you." |
| the Fury first takes a party member | "The Fury has %s. It ends when the hunger is fed or burns out." |
| Álvar's health first falls under a third in a fight | "The west door is a way out. The guard will close ranks again." |

- [ ] **Step 1: Write the failing tests:** Íñigo's first talk is exactly three lines and sets the flags it set before; each hint shows at its moment and not before, once only across a reload, never over a conversation or a card, and is dropped if its moment has passed; a whole vault fight played by the scripted Player from Task 1 shows each hint at most once and no two at the same time.
- [ ] **Step 2: Run them; they fail.**
- [ ] **Step 3: Implement** (the speech; the hints, one small node rather than more branches in `Main`).
- [ ] **Step 4: Full suite; browser tests; update `README.md` (how the fight is meant to be played; the hints) and append "Amendments made while building" and "Carried forward" to this plan.**
- [ ] **Step 5: Look at it.** Frames of each hint in English and two in Spanish, and of Íñigo's three lines. Read the texts back.
- [ ] **Step 6: Commit** — `feat: cut Íñigo's rules to three lines`, `feat: teach the fight's rules when they first apply`, `docs: describe the fight and its hints; record milestone 5b`

---

### After the last task: put it online

Once the final review's fixes are in and the suites are green, the controller runs `ops/deploy-fly.sh`, checks the live site (a new game reaches the Fragua; Íñigo speaks three lines), and reports with the balance table and the frames.
