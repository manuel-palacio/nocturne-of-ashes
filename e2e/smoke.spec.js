// e2e/smoke.spec.js
const { test, expect } = require('@playwright/test');

const state = (page) => page.evaluate(() => { window.nocturneProbe(); return window.nocturneState; });

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

test('the room loads without errors and shows the player and six enemies', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  const s = await state(page);
  expect(s.health).toBe(120);
  expect(s.enemies).toBe(6);
  expect(s.fallen).toBe(false);
  await page.screenshot({ path: 'build/e2e/room.png' });
  expect(errors).toEqual([]);
});

test('a click on the floor walks the character there', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  const start = (await state(page)).pos;
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.pos;
    return Math.hypot(p[0] - from[0], p[1] - from[1]) > 1.5;
  }, start, { timeout: 15000 });
  expect(errors).toEqual([]);
});

test('the room holds 30 frames a second', async ({ page }) => {
  test.setTimeout(90000);
  await open(page, 'skirmish=1&probe=1&calm=1');
  await page.waitForTimeout(3000);
  expect((await state(page)).fps).toBeGreaterThanOrEqual(30);
});
