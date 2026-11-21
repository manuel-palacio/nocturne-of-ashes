// e2e/public.spec.js
// The public flavour (build/public, `ops/build-web.sh public`), the one the site serves: the test
// parameters do nothing there, so a link with `?probe=1&fresh=1` neither wipes a visitor's save nor
// exposes the probe. Runs in the `public` project only, in Chromium, against its own server.
//
// With no probe to ask, the game is read as a visitor sees it, and the save where the browser keeps
// it: the save is made as a player makes one (New game: entering the haven is a checkpoint), and read
// back from the IndexedDB store the engine keeps `user://` in.
const { test, expect } = require('@playwright/test');

// Where the engine keeps `user://save.json` in the browser.
const SAVE_KEY = '/userfs/godot/app_userdata/Nocturne of Ashes/save.json';
// The title's buttons, in CSS pixels at 1280 × 720.
const MENU = { x: 480, y: 180, width: 320, height: 380 };

// The save's text as the browser holds it, or null when there is none.
const savedText = (page) => page.evaluate(async (key) => {
  const db = await new Promise((resolve, reject) => {
    const open = indexedDB.open('/userfs');
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
  if (!db.objectStoreNames.contains('FILE_DATA')) return null;
  const entry = await new Promise((resolve, reject) => {
    const get = db.transaction('FILE_DATA').objectStore('FILE_DATA').get(key);
    get.onsuccess = () => resolve(get.result);
    get.onerror = () => reject(get.error);
  });
  db.close();
  return entry && entry.contents ? new TextDecoder().decode(entry.contents) : null;
}, SAVE_KEY);

// Opens the page with the query `query` at 1280 × 720 and waits until the engine has started (the
// page's loading overlay is gone) and three seconds more; returns the list the page's errors go in.
async function visit(page, query) {
  const errors = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', (err) => errors.push(err.message));
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/' + query);
  await page.waitForFunction(() => document.getElementById('status') === null, null, { timeout: 60000 });
  await page.waitForTimeout(3000);
  return errors;
}

// The share of pixels that differ clearly between two PNG screenshots of the same size, decoded in
// the page.
const difference = (page, a, b) => page.evaluate(async ([a, b]) => {
  const pixels = async (base64) => {
    const bitmap = await createImageBitmap(await (await fetch('data:image/png;base64,' + base64)).blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, 0, 0);
    return context.getImageData(0, 0, bitmap.width, bitmap.height).data;
  };
  const [p, q] = [await pixels(a), await pixels(b)];
  let differ = 0;
  for (let i = 0; i < p.length; i += 4) {
    if (Math.abs(p[i] - q[i]) + Math.abs(p[i + 1] - q[i + 1]) + Math.abs(p[i + 2] - q[i + 2]) > 60) differ++;
  }
  return differ / (p.length / 4);
}, [a.toString('base64'), b.toString('base64')]);

test('the test parameters do nothing: a save survives ?probe=1&fresh=1 and there is no probe', async ({ page }) => {
  test.setTimeout(180000);
  // A first visit: the title with no save, then New game, whose first room saves.
  let errors = await visit(page, '');
  expect(await savedText(page)).toBeNull();
  const noSave = await page.screenshot({ clip: MENU });
  await page.keyboard.press('Enter');
  await expect.poll(() => savedText(page), { timeout: 30000 }).not.toBeNull();
  const save = await savedText(page);
  expect(JSON.parse(save).room).toBe('haven');
  expect(errors).toEqual([]);

  // A visitor coming back: the title, with Continue.
  errors = await visit(page, '');
  const visitor = await page.screenshot({ clip: MENU });
  expect(errors).toEqual([]);

  // The crafted link: the same title, the save untouched, no probe.
  errors = await visit(page, '?probe=1&fresh=1');
  expect(await page.evaluate(() => typeof window.nocturneProbe)).toBe('undefined');
  expect(await page.evaluate(() => window.nocturneStarted)).toBeUndefined();
  expect(await page.evaluate(() => window.nocturneState)).toBeUndefined();
  const crafted = await page.screenshot({ clip: MENU });
  await page.screenshot({ path: 'build/e2e/public-title.png' });
  expect(await savedText(page)).toBe(save);
  // As the returning visitor's title (Continue offered), not as the first visit's (New game alone).
  expect(await difference(page, crafted, visitor)).toBeLessThan(0.01);
  expect(await difference(page, crafted, noSave)).toBeGreaterThan(0.03);
  expect(errors).toEqual([]);
});
