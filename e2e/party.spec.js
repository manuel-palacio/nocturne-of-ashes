// e2e/party.spec.js
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

test('the party of three starts with Álvar selected', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  const s = await state(page);
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar', 'Zahra', 'Gonzalo']);
  expect(s.party.map((m) => m.blood)).toEqual([60, 60, 60]);
  expect(s.selected).toBe(0);
  expect(s.enemies).toBe(6);
  await page.screenshot({ path: 'build/e2e/party.png' });
  expect(errors).toEqual([]);
});

test('Tab selects the next member and the companions follow the leader', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  await page.keyboard.press('Tab');
  await page.waitForFunction(() => { window.nocturneProbe(); return window.nocturneState.selected === 1; });
  const before = await state(page);
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.7, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.party;
    return p[1].pos[0] - from[1] > 1.5 && p[0].pos[0] - from[0] > 0.5;
  }, [before.party[0].pos[0], before.party[1].pos[0]], { timeout: 20000 });
  expect(errors).toEqual([]);
});

test('Space pauses the world and orders wait for it', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  await page.keyboard.press('Space');
  await page.waitForFunction(() => { window.nocturneProbe(); return window.nocturneState.paused; });
  const before = (await state(page)).party[0].pos;
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + box.width * 0.7, box.y + box.height * 0.5);
  await page.waitForTimeout(1500);
  const held = (await state(page)).party[0].pos;
  expect(Math.hypot(held[0] - before[0], held[1] - before[1])).toBeLessThan(0.1);
  await page.keyboard.press('Space');
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    return window.nocturneState.party[0].pos[0] - from > 1.0;
  }, before[0], { timeout: 15000 });
  expect(errors).toEqual([]);
});

test('key 1 spends Blood on Iron Sinew', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'skirmish=1&probe=1&calm=1');
  await page.keyboard.press('1');
  await page.waitForFunction(() => {
    window.nocturneProbe();
    const m = window.nocturneState.party[0];
    return m.blood === 40 && m.effects.includes('iron_sinew');
  }, null, { timeout: 5000 });
  expect(errors).toEqual([]);
});

test('a full fight runs to an end, and a fall can be restarted', async ({ page }) => {
  test.setTimeout(240000);
  const errors = await open(page, 'skirmish=1&probe=1');
  const box = await page.locator('canvas').boundingBox();
  for (let i = 0; i < 40; i++) {
    const s = await state(page);
    if (s.fallen || s.cleared) break;
    await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
    await page.waitForTimeout(3000);
  }
  const end = await state(page);
  expect(end.fallen || end.cleared).toBe(true);
  expect(end.fps).toBeGreaterThanOrEqual(30);
  if (end.fallen) {
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => {
      window.nocturneProbe();
      const s = window.nocturneState;
      return !s.fallen && s.enemies === 6 && s.party.every((m) => m.alive) && s.selected === 0;
    }, null, { timeout: 15000 });
  }
  expect(errors).toEqual([]);
});
