// e2e/story.spec.js
const { test, expect } = require('@playwright/test');
const { state, open, until, talkThrough } = require('./helpers');

test('a new game wakes in the haven and Malakor speaks first', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  const s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.speaker).toBe('Malakor');
  expect(s.party.map((m) => m.name)).toEqual(['Brother Álvar']);
  expect(s.conscience).toBe(7);
  await page.screenshot({ path: 'build/e2e/waking.png' });
  await talkThrough(page, '1');
  const after = await state(page);
  expect(after.flags).toContain('met_malakor');
  expect(after.saved).toBe(true);
  expect(errors).toEqual([]);
});

test('progress survives a page reload', async ({ page }) => {
  test.setTimeout(120000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await talkThrough(page, '1');
  // A second conversation, so the save is replaced more than once before the reload.
  const at = (await state(page)).people['The captive'];
  const box = await page.locator('canvas').boundingBox();
  await page.mouse.click(box.x + at[0], box.y + at[1]);
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; }, null, 20000);
  await talkThrough(page, '3');
  await page.goto('/?probe=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  const s = await state(page);
  expect(s.room).toBe('haven');
  expect(s.talking).toBe(false);
  expect(s.flags).toContain('met_malakor');
  expect(s.flags).toContain('captive_done');
  expect(s.conscience).toBe(8);
  expect(errors).toEqual([]);
});

test('a reload in the middle of a conversation undoes it', async ({ page }) => {
  test.setTimeout(120000);
  await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  await page.goto('/?probe=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  const s = await state(page);
  expect(s.flags).not.toContain('met_malakor');
  expect(s.speaker).toBe('Malakor');
});

test('the title leads into a new game', async ({ page }) => {
  test.setTimeout(90000);
  const errors = await open(page, 'probe=1&fresh=1&title=1');
  const s = await state(page);
  expect(s.title).toBe(true);
  expect(s.room).toBe('');
  await page.screenshot({ path: 'build/e2e/title.png' });
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); const t = window.nocturneState; return !t.title && t.room === 'haven'; });
  expect(errors).toEqual([]);
});

test('a double click on New game with a save keeps the save and asks', async ({ page }) => {
  test.setTimeout(120000);
  // A save: the vault's start is a checkpoint.
  await open(page, 'probe=1&fresh=1&at=vault&calm=1');
  expect((await state(page)).saved).toBe(true);
  const errors = await open(page, 'probe=1&title=1');
  const s = await state(page);
  expect(s.title).toBe(true);
  expect(s.asking).toBe(false);
  const box = await page.locator('canvas').boundingBox();
  const [x, y] = s.new_game;
  // Two presses 0.1 s apart, at New game's place, where No takes over after the first.
  await page.mouse.click(box.x + x, box.y + y);
  await page.waitForTimeout(100);
  await page.mouse.click(box.x + x, box.y + y);
  await page.waitForTimeout(1000);
  const after = await state(page);
  expect(after.title).toBe(true);
  expect(after.asking).toBe(true);
  expect(after.saved).toBe(true);
  expect(after.room).toBe('');
  expect(errors).toEqual([]);
});

test('clicking someone starts a conversation and a choice moves Conscience', async ({ page }) => {
  test.setTimeout(120000);
  const errors = await open(page, 'probe=1&fresh=1');
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
  await talkThrough(page, '1');
  const at = (await state(page)).people['The captive'];
  const box = await page.locator('canvas').boundingBox();
  expect(at[0]).toBeGreaterThan(0);
  expect(at[0]).toBeLessThan(box.width);
  expect(at[1]).toBeGreaterThan(0);
  expect(at[1]).toBeLessThan(box.height);
  await page.mouse.click(box.x + at[0], box.y + at[1]);
  await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; }, null, 20000);
  expect((await state(page)).speaker).toBe('The captive');
  await talkThrough(page, '3');
  const after = await state(page);
  expect(after.conscience).toBe(8);
  expect(after.flags).toContain('captive_done');
  expect(errors).toEqual([]);
});

test('a fall in the vault reloads the checkpoint', async ({ page }) => {
  test.setTimeout(180000);
  const errors = await open(page, 'probe=1&fresh=1&at=vault&frail=1');
  const start = await state(page);
  expect(start.room).toBe('vault');
  expect(start.party.length).toBe(3);
  const box = await page.locator('canvas').boundingBox();
  for (let i = 0; i < 25; i++) {
    if ((await state(page)).fallen) break;
    await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
    await page.waitForTimeout(2000);
  }
  expect((await state(page)).fallen).toBe(true);
  await page.keyboard.press('Enter');
  await until(page, () => { window.nocturneProbe(); const s = window.nocturneState; return !s.fallen && s.room === 'vault' && s.enemies === 6; });
  expect((await state(page)).party.length).toBe(3);
  expect(errors).toEqual([]);
});

test('Spanish on request', async ({ page }) => {
  test.setTimeout(90000);
  await open(page, 'probe=1&skirmish=1&lang=es');
  const s = await state(page);
  expect(s.party[0].name).toBe('Hermano Álvar');
});
