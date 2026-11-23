// e2e/helpers.js
// What the browser tests share: opening the game with the probe, reading its state, waiting on it and
// talking through a conversation, and clicking towards someone or something to use it.
const { expect } = require('@playwright/test');

// The game's state as the probe (`?probe=1`) reports it.
const state = (page) => page.evaluate(() => { window.nocturneProbe(); return window.nocturneState; });

// Opens the game at 1280 × 720 with the page query `query`, waits until it has started and a second
// more, and returns the list the page's errors are collected in.
async function open(page, query) {
  const errors = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', (err) => errors.push(err.message));
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?' + query);
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.waitForTimeout(1000);
  return errors;
}

// Waits until `fn(arg)` holds in the page.
const until = (page, fn, arg, timeout = 15000) => page.waitForFunction(fn, arg, { timeout });

// Presses Enter through plain lines and `key` at each choice until the conversation ends.
async function talkThrough(page, key) {
  for (let i = 0; i < 60; i++) {
    const s = await state(page);
    if (!s.talking) return;
    await page.keyboard.press(s.choices.length > 0 ? key : 'Enter');
    await page.waitForTimeout(250);
  }
  throw new Error('the conversation did not end');
}

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

module.exports = { state, open, until, talkThrough, usable, clickTowards, use };
