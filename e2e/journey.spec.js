// e2e/journey.spec.js
// The story from New game to the last lock and back by Continue: the waking, the smith, Malakor before
// the party is gathered and the barred stair, the captive, Zahra and Gonzalo joining, Malakor's order
// and the letter, the stair down, the vault fought to cleared, the closing card that says the story
// rests there, the last lock, then a reload and Continue, which does not show the card again. `calm=1` keeps it deterministic: the crusaders stand still and fall to the party's blows.
const { test, expect } = require('@playwright/test');
const { state, open, until, talkThrough } = require('./helpers');

// A screen point a click can reach: clear of the party panels on the left, the Gift bar at the bottom
// and the edges.
const usable = (at, view) => at && at[0] > 240 && at[0] < view[0] - 30 && at[1] > 30 && at[1] < view[1] - 90;

// Clicks a point `at` (CSS pixels relative to the canvas) if a click can reach it, else a point on
// the way to it, 220 px from the middle of the screen, so Álvar walks towards it.
async function clickTowards(page, at) {
  const box = await page.locator('canvas').boundingBox();
  const s = await state(page);
  let [x, y] = at;
  if (!usable(at, s.view)) {
    const cx = s.view[0] / 2, cy = s.view[1] / 2;
    const k = Math.min(1, 220 / Math.hypot(at[0] - cx, at[1] - cy));
    x = cx + (at[0] - cx) * k;
    y = cy + (at[1] - cy) * k;
  }
  await page.mouse.click(box.x + x, box.y + y);
}

// Walks to and uses the person or door `name` until `done(state)` holds.
async function use(page, name, done) {
  for (let i = 0; i < 30; i++) {
    const s = await state(page);
    if (done(s)) return;
    const at = s.people[name];
    if (!at) throw new Error(`${name} is not on show; on show: ${Object.keys(s.people).join(', ')}`);
    await clickTowards(page, at);
    await page.waitForTimeout(1300);
  }
  expect(done(await state(page)), `using ${name}`).toBe(true);
}

// Talks to `name`, taking choice `key` at each choice, and returns the lines spoken.
async function talkTo(page, name, key) {
  await use(page, name, (s) => s.talking);
  const lines = [];
  for (let i = 0; i < 60; i++) {
    const s = await state(page);
    if (!s.talking) return lines;
    if (lines.length === 0 || lines[lines.length - 1] !== s.line) lines.push(s.line);
    await page.keyboard.press(s.choices.length > 0 ? key : 'Enter');
    await page.waitForTimeout(250);
  }
  throw new Error(`the conversation with ${name} did not end`);
}

const talking = () => { window.nocturneProbe(); return window.nocturneState.talking; };

test('the story from New game to the last lock, and Continue after a reload', async ({ page }) => {
  test.setTimeout(300000);
  const errors = await open(page, 'probe=1&fresh=1&title=1&calm=1');
  expect((await state(page)).title).toBe(true);

  // New game, and the waking.
  await page.keyboard.press('Enter');
  await until(page, talking, null, 30000);
  expect((await state(page)).speaker).toBe('Malakor');
  await talkThrough(page, '1');
  let s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.flags).toContain('met_malakor');
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar']);

  // The smith tells how things are.
  const smith = await talkTo(page, 'Íñigo', '1');
  expect(smith.some((line) => line.includes('The Blood in you is not your own now'))).toBe(true);

  // Malakor before the party is gathered: he sends Álvar to find them, and the stair stays barred.
  const early = await talkTo(page, 'Malakor', '1');
  expect(early.some((line) => line.includes('Zahra and Gonzalo go with you'))).toBe(true);
  expect((await state(page)).flags).not.toContain('order_given');
  await use(page, 'StairDoor', (t) => t.notice !== '' || t.room !== 'haven');
  s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.notice).toBe('The stair is barred until Malakor says otherwise');

  // The captive, left be: Conscience 7 → 8.
  await talkTo(page, 'The captive', '3');
  s = await state(page);
  expect(s.conscience).toBe(8);
  expect(s.flags).toEqual(expect.arrayContaining(['captive_done', 'captive_spared']));

  // Zahra and Gonzalo join.
  await talkTo(page, 'Zahra', '1');
  await page.waitForTimeout(500);
  await talkTo(page, 'Gonzalo', '1');
  await page.waitForTimeout(800);
  s = await state(page);
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar', 'Zahra', 'Gonzalo']);
  expect(s.flags).toEqual(expect.arrayContaining(['zahra_joined', 'gonzalo_joined']));

  // Malakor's order, and the letter said to have burned: Conscience 8 → 9.
  await talkTo(page, 'Malakor', '2');
  s = await state(page);
  expect(s.conscience).toBe(9);
  expect(s.flags).toEqual(expect.arrayContaining(['order_given', 'kept_letter']));
  expect(s.flags).not.toContain('gave_letter');

  // The stair door, open now: down to the vault with the party.
  await use(page, 'StairDoor', (t) => t.room === 'vault');
  await page.waitForTimeout(1500);
  s = await state(page);
  expect(s.room).toBe('vault');
  expect(s.party.length).toBe(3);
  expect(s.enemies).toBe(6);
  expect(s.cleared).toBe(false);

  // The fight, to cleared: Álvar is sent at the nearest crusader he can reach until none stands.
  for (let i = 0; i < 150; i++) {
    s = await state(page);
    if (s.cleared) break;
    expect(s.fallen).toBe(false);
    const foe = s.foes.find((at) => usable(at, s.view)) || s.foes[0];
    await clickTowards(page, foe || [s.view[0] * 0.75, s.view[1] * 0.5]);
    await page.waitForTimeout(1200);
  }
  s = await state(page);
  expect(s.cleared).toBe(true);
  expect(s.enemies).toBe(0);

  // The closing card says the story rests here; Enter closes it.
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.closing; });
  await page.waitForTimeout(500);
  await page.screenshot({ path: `build/e2e/journey-cleared-${test.info().project.name}.png` });
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); return !window.nocturneState.closing; });
  s = await state(page);
  expect(s.flags).toContain('rest_shown');

  // The last lock does not yield, and says where the story rests.
  await use(page, 'LastLock', (t) => t.notice === 'The last lock does not yield. This is where the story rests, for now.');

  // A reload, and Continue from the title: the cleared vault, the party and Conscience come back.
  await page.goto('/?probe=1&title=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.waitForTimeout(1000);
  s = await state(page);
  expect(s.title).toBe(true);
  expect(s.saved).toBe(true);
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); const t = window.nocturneState; return !t.title && t.room !== ''; }, null, 30000);
  await page.waitForTimeout(1000);
  s = await state(page);
  expect(s.room).toBe('vault');
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar', 'Zahra', 'Gonzalo']);
  expect(s.conscience).toBe(9);
  expect(s.flags).toEqual(expect.arrayContaining(['order_given', 'kept_letter', 'captive_spared']));
  expect(s.cleared).toBe(true);
  expect(s.enemies).toBe(0);
  expect(s.talking).toBe(false);
  // The card was seen: not again, and a short line says the story rests here.
  expect(s.closing).toBe(false);
  expect(s.notice).toBe('The vault is quiet. The story rests here, for now.');
  expect(errors).toEqual([]);
});
