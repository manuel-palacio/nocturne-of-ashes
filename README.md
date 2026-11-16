# Nocturne of Ashes

A party-based Gothic action RPG for the web browser, built with Godot 4.7: a devout
medieval warrior turned against his will, a love that spans centuries, a forced sleep and
a waking in the present day. The first deliverable is a vertical slice set in medieval
Toledo that proves the core loop is fun: explore a hub, talk, feed, fight with a small
party, use blood powers and make choices that cost something.

Run the tests: `ops/test.sh`

Build for the browser: `ops/build-web.sh`

Browser tests: `npx playwright test` (after `npm install` and a browser build)

The Chromium run opens a browser window, because headless Chromium renders WebGL in software and cannot hold the frame rate.

- Design: [docs/superpowers/specs/2026-11-15-vertical-slice-design.md](docs/superpowers/specs/2026-11-15-vertical-slice-design.md)
- Plan: [docs/superpowers/plans/2026-11-15-milestone-1-first-room.md](docs/superpowers/plans/2026-11-15-milestone-1-first-room.md)

## Controls

- Left click on the floor to move the selected party member, on an enemy to attack it.
- Left click on a weakened enemy to feed on it.
- Left click on a companion, or press Tab, to select another party member.
- 1 and 2 use the selected member's Gifts; a Gift that needs a target waits for a click on one.
- Escape (or a right click) cancels a Gift's targeting.
- Space pauses and resumes the world; orders given while paused begin on resume.
- Q and E turn the camera; the mouse wheel zooms.
- Enter restarts the room after Álvar falls.
