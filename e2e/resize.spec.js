// e2e/resize.spec.js
const { test, expect } = require('@playwright/test');

const state = (page) => page.evaluate(() => { window.nocturneProbe(); return window.nocturneState; });

test('after a resize and a lost focus the canvas fills the window and clicks still land', async ({ page }) => {
  test.setTimeout(90000);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?probe=1&calm=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000 });
  await page.setViewportSize({ width: 900, height: 600 });
  await page.evaluate(() => { window.dispatchEvent(new Event('blur')); window.dispatchEvent(new Event('focus')); });
  await page.waitForTimeout(1000);
  const box = await page.locator('canvas').boundingBox();
  expect(Math.round(box.width)).toBe(900);
  expect(Math.round(box.height)).toBe(600);
  expect((await state(page)).view).toEqual([900, 600]);
  const start = (await state(page)).pos;
  await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.5);
  await page.waitForFunction((from) => {
    window.nocturneProbe();
    const p = window.nocturneState.pos;
    return p[0] - from[0] > 1.0;  // the click was east of the character, so it must walk east
  }, start, { timeout: 15000 });
});
