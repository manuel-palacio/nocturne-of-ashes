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

- Design: [docs/superpowers/specs/2026-11-15-vertical-slice-design.md](docs/superpowers/specs/2026-11-15-vertical-slice-design.md)
- Plans: [docs/superpowers/plans/2026-11-15-milestone-1-first-room.md](docs/superpowers/plans/2026-11-15-milestone-1-first-room.md), [docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md](docs/superpowers/plans/2026-11-16-milestone-2-party-and-blood.md), [docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md](docs/superpowers/plans/2026-11-16-milestone-3-talk-and-choose.md)

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
