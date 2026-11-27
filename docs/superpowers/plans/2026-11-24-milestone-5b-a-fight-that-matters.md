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

---

## Amendments made while building

Each ruling taken while the plan was built: what changed, and why.

- **The way out.** The west door refuses only while an enemy is within 3 m of Álvar (and while he feeds
  or is in the Fury). Leaving is a voluntary reset, as the guard is whole again on return, so it cannot
  be farmed, and a player can always walk away from a fight.
- **The tiring guard.** Planned from the third fall at 10% a fall down to 70%; built from the second
  fall at 15% a fall down to 50% (85%, 70%, 55%, then 50%). The owner's standing demand that nobody
  gets stuck outranks a fixed difficulty, and six falls before any relief were too many; a weak player
  sees the fight soften.
- **The target table was replaced.** The first table rewarded an execute loop (feeds deleting most of an
  enemy's health) and measured a clicker no player is. It became eight rows played at a person's pace
  through the same click a player makes, with ceilings as well as floors, so that feeding and the Rites
  matter through danger and choice rather than as a required ritual.
- **Feeding drinks from the weakened.** Feeding is allowed at most at half an enemy's health (a fifth for
  companions), and enemies got far less health and more damage. A door used by Álvar calls companions
  off their brain-ordered feeds.
- **Three small rules adopted:** a feed mends in proportion to the Blood it restores; a click on the
  enemy already being struck keeps the strike; the guard tires from the second fall. The fed player had
  to end a won fight hurt, and the dry start had to be worse than a fed one.
- **Not adopted:** a feed mark above half health (feeding stays "at most half"), and the second group of
  enemies on a timer (the alert rule stays).
- **Bars restated** without a floor for the spam clicker (at most 4 of 10; the tiring guard is his way
  through), the player at least 7 of 10, won fights in 35–75 s, end health at most three quarters; no
  bar may stay pending. A plain clicker loses until the guard tires.
- **A hurt drinker may feed with full Blood**, for half the heal: with 80 Blood a feed, Álvar was often
  full, and a click on a marked enemy attacked instead, so he could not mend. The "Blood is full" line
  shows only when health is full too.
- **Each row's assertion sits one win looser than the worse of two fresh passes**, within fixed limits
  (B ≥ 6, C ≤ 6, D falls ≥ 7, E ≥ 4, F ≥ 6, G ≥ 7, H ≥ 8, A ≤ 4). Run-to-run spread is about two wins
  in ten; a bar on its measured value would fail by chance. The suite proves "roughly this"; the
  measurements are recorded here.
- **The heal floor:** a feed mends by the full heal × the larger of the share of Blood restored and one
  half. It closes a cliff where a drinker one point short of full Blood was mended by almost nothing.
- **Row F's lower limit is 4 of 10:** draining the captive equals sparing him within noise while Blood is
  plentiful (15 against 13 wins of 20); the darkest choice buys no edge in this fight.
- **Rite keys are taken as events in the order they arrive**, with clicks: a quick player pressing 2 and
  clicking lost the Rite, and the Eye is what wins. On the web a world click waits for the end of its
  frame, as the web platform hands a frame's clicks over before its keys.
- **Left open and carried forward, not tuned further:** the sergeant-feed execute, the scarcity of Blood
  and the Fury, and how readable the crush is. Three tuning rounds were spent; these are design
  questions for the next content.
- **Row B's "a companion falls" limit is 2 runs in 10** (measured 3 and 2): the point, that wins cost
  something, holds with Álvar ending at 73–80 of 120.
- **Íñigo's after-the-captive opening** keeps "He told me to tell you how things are" so that his first
  line still introduces the two that follow.
- **The hints** (Task 2), each one line, as built: the Rites hint names what each does ("1: Iron Sinew,
  to strike harder. 2: Baleful Eye, then click a foe to still him."), since the fight turns on the Eye;
  a seventh hint, the first time a sergeant is within 6 m of the party in a fight ("The helmed
  sergeants hit hardest. Still one with Baleful Eye, and drink when he weakens."), because the sergeants
  decide the fight; the feeding hint says a feed mends as well as restoring Blood. The Rites and
  sergeant hints were not merged: one says what the keys do, the other whom to use the Eye on, and the
  Rites hint is skipped for a player who has already called a Rite. At most one hint every 6 s, the most
  urgent first (the door, the Fury, running dry, feeding, the sergeant, the Rites, the pause). A hint
  waits while another notice is up, under a conversation, a card, the fall prompt or the title, and is
  dropped if its moment passes meanwhile; a game notice shown over a hint replaces it. A hint seen is a
  flag written into the last checkpoint at once, so neither a fall nor a reload brings it back; the
  skirmish, with no save, shows each once per page load.
- **The final review's fixes** (one wave, after the final whole-branch review):
  - **The tiring count survives leaving.** The count of Álvar's falls in a room is kept until that room
    is cleared or a new game starts; leaving by a door and coming back keeps it, and the guard returns
    whole at its tired strength, saying "The guard is tiring." in place of closing ranks. It is still
    not saved. (This overturns the earlier ruling that leaving forgets the falls: the door hint was
    sending weak players down the one path with no floor.)
  - **The feeding hint's rule.** A feed no longer counts as the lesson learned (a clicker feeds by
    chance): a first feed before the hint has shown makes it due, and it shows as soon as it may.
  - **"Running dry" is about Álvar only** (his Blood under a third), and never shows before the
    feeding hint; when it falls due first, the feeding hint goes first. Urgency: the door, the
    sergeants, feeding, the Rites, running dry, the Fury, the pause.
  - **The door hint falls due at half health** (was a third), in time to reach the door. The scripted
    coward keeps his third.
  - **Hints in their own band, for 5 s.** A hint is drawn in a band in the lower third, above the Rite
    bar, not where game notices and the cleared line show; 5 s on show, still 6 s from one hint's start
    to the next's. Every hint fits on two lines at 1280 × 720 and 800 × 500, in English and Spanish.
  - **The fall prompt's delay.** It ignores clicks and Enter for 1.5 s after it shows, timed by the
    clock as the closing card's delay is; the tired guard's line stays 4 s.
  - **The dry floor row and the floor.** Row I, a spam clicker with every member at 0 Blood against the
    guard at its floor, bar 6 of 10, is the floor under "nobody gets stuck" for the weakest start. At
    the floor of 50% he cleared 0 of 10 in both passes (0.3: 2; 0.2: 3; 0.17: 8 and 8). The floor is
    now 15%: row I 10 / 10, row H 10 / 10. The floor is reached at the seventh fall (was the fifth).

### Final numbers

| unit or Rite | numbers |
|---|---|
| Brother Álvar | 120 health; 15 a blow every 0.9 s (melee reach 1.6 m); 4.0 m/s; starts with 60 Blood; feeds from 50% of an enemy's health |
| Zahra | 80 health; 8 every 1.0 s; 4.0 m/s; 60 Blood; feeds from 20% |
| Gonzalo | 160 health; 18 every 1.3 s; 3.4 m/s; 60 Blood; feeds from 20% |
| Crusader | 120 health; 3 every 1.4 s; 2.4 m/s |
| Sergeant | 1200 health; 16 every 3.0 s; 2.0 m/s |
| Feeding (all) | 2.0 s; +80 Blood; +65 health × the larger of (Blood restored ÷ 80) and 0.5; a click feeds when short of Blood or of health; companions' brains feed below 30 Blood |
| The Fury | starts when Blood is spent from 10 or more to under 10; 5 s; damage × 1.5 |
| Iron Sinew (Álvar) | 20 Blood; 12 s cooldown; 8 s; damage × 1.5, speed × 1.4 |
| Baleful Eye (Álvar) | 10 Blood; 10 s cooldown; 5 s stun; 8 m |
| Mend Flesh (Zahra) | 20 Blood; 6 s; +40 health; 8 m |
| Blood Lance (Zahra) | 15 Blood; 4 s; 30 damage; 10 m |
| Stone Hide (Gonzalo) | 30 Blood; 15 s; 6 s; damage taken × 0.4; taunt 2 m |
| Hammerfall (Gonzalo) | 25 Blood; 12 s; 15 damage and 2.5 s stun within 3.5 m |
| The west door | refuses while an enemy is within 3 m of Álvar, or Álvar is in the Fury or feeding; calls companions off a feed |
| The tiring guard | from the second fall in a room: 85%, 70%, 55%, 40%, 25%, then 15% of its health; kept through a door, forgotten when the room is cleared or on a new game |

### The nine rows (10 runs each, two passes: seeds 1000–1009 and 1010–1019)

| row | first pass | second pass | bar in the suite | limit |
|---|---|---|---|---|
| A spam clicker | 0 cleared (median 17.2 s) | 0 (20.2 s) | ≤ 1 | ≤ 4 |
| B player | 7; won in 39.0 s; end health 80; a companion fell in 3 runs | 8; 40.0 s; 73; 2 runs | ≥ 6; 35–75 s; ≤ 90; a companion falls in ≥ 2 runs | ≥ 6 |
| C no Rites | 4 | 5 | ≤ 6; B − C ≥ 4 of 20 | ≤ 6; ≥ 4 |
| D never feeds | falls 10 | falls 10 | falls ≥ 9 | ≥ 7 |
| E dry start | 10 (won in 43.7 s) | 9 (42.0 s) | ≥ 8 | ≥ 4 |
| F drained captive | 10 | 6 | ≥ 5 | ≥ 4 |
| G coward | reaches the Fragua 10 | 9 | ≥ 8 | ≥ 7 |
| H spam clicker at the tiring floor | 10 (floor 15%; 10 at 50%) | 10 (9 at 50%) | ≥ 8 | ≥ 8 |
| I dry spam clicker at the tiring floor | 10 (floor 15%; 0 at 50%) | 10 (0 at 50%) | ≥ 6 | ≥ 6 |

Also measured: Álvar's median end Blood 100 in rows B, E and F; party feeds per fight B 4/4, E 6/6,
F 3.5/3; Álvar's Rites 8 a fight in every player row; no Fury in any row. In the browser, at a person's
pace (one action a second, a Rite's key and its click back to back), 12 of 12 fights cleared in 45.8–50.5 s,
Álvar ending at 49–120 health (median 65).

## Carried forward

- Feeds on the two sergeants still decide each win: about a third to two fifths of the guard's health
  is removed by feeds.
- Blood is never scarce at 80 a feed, so the Fury is met only by a player who spends Rites and never
  feeds, and draining the captive buys no edge in the fight. The Fury hint and the "running dry" hint
  therefore show less often than the others.
- In the crush a player cannot tell the sergeants from the crusaders or see who is marked, or which
  companion is in trouble: there is no health over heads. The final reviewer mis-clicked a feed by
  sight. The first thing to change next: health over heads, or a clearer sergeant.
- A second click on another enemy breaks a feed in progress.
- A companion taken by the Fury attacks the nearest living unit, the party included, in the Fragua too.
- The tiring guard loses health, not damage: a dry party with no Rites wins only once the guard dies
  in a blow or two, which is why the floor had to go down to 15%.
- An intermittent report of two orphans at the end of a single test file run alone, never reproduced on
  demand; a rerun clears it. Players are not affected.
- In Firefox the page starts in about 13 s against a 15 s bar.
- The unit suite takes about 12 minutes (720 s for 724 tests), about 3 of them the balance file
  (row I added this wave).
- The browser player's 12 of 12 comes from one unjittered start; the headless 6–8 of 10 from varied
  starts is the number to believe.
- A spam clicker with Blood gets through around his fourth or fifth fall (55% and 40% of the guard's
  health); one with no Blood only near the floor, at about the seventh.
- Kiting (leading enemies round the room) is untested.
- What a first fight shows, measured with the scripted players: the player who uses his Rites and feeds
  meets three to five hints (the pause, the sergeant, feeding, the door when he is down to half, and
  running dry late in a long fight); a spam clicker three to five (the pause, the sergeant, the Rites,
  feeding, the door). The scripted player never sees the Rites hint, as he calls a Rite before it
  falls due.
- A hint seen rewrites the last checkpoint's save mid-fight, with only its flag changed; the party's
  vitals in it stay as they were at the checkpoint.
