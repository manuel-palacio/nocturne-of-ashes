// e2e/look.spec.js
// The browser budget: frame rate with everyone on screen, the time a first load takes, and the frames
// the owner is shown (build/e2e/look-<frame>-<browser>.png, 1280 × 720 at twice the pixel density).
const { test, expect } = require('@playwright/test');
const fs = require('fs');

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

// Where a frame for the owner is saved, by the browser that drew it.
const frame = (name) => `build/e2e/look-${name}-${test.info().project.name}.png`;

const inside = (at, box) => at[0] > 0 && at[0] < box.width && at[1] > 0 && at[1] < box.height;

// Waits until the selected member has stopped walking.
async function settle(page) {
  let last = (await state(page)).pos;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(250);
    const now = (await state(page)).pos;
    if (Math.hypot(now[0] - last[0], now[1] - last[1]) < 0.01) return;
    last = now;
  }
}

// Walks Álvar past the first group of crusaders (x ≈ 1) to between it and the second (x ≈ 9), so that
// all six come at the party at once, then lets it fight for ten seconds without further orders. Logs
// the frame rate of each of those seconds.
async function fightForTenSeconds(page) {
  const box = await page.locator('canvas').boundingBox();
  const full = (await state(page)).party.map((m) => m.health);
  for (let i = 0; i < 15 && (await state(page)).pos[0] < 3; i++) {
    await page.mouse.click(box.x + box.width * 0.8, box.y + box.height * 0.5);
    await page.waitForTimeout(800);
  }
  await until(page, (from) => {
    window.nocturneProbe();
    return window.nocturneState.party.some((m, k) => m.health < from[k]);
  }, full, 20000);
  await page.screenshot({ path: `build/e2e/budget-skirmish-${test.info().project.name}.png` });
  const rates = [];
  for (let i = 0; i < 10; i++) {
    await page.waitForTimeout(1000);
    rates.push((await state(page)).fps);
  }
  console.log(`fighting, frames a second: ${rates.join(' ')}`);
}

test.describe('the frame rate with everyone on screen', () => {
  test('the skirmish holds 30 frames a second with the party and six crusaders fighting', async ({ page }) => {
    test.setTimeout(120000);
    const errors = await open(page, 'skirmish=1&probe=1');
    await fightForTenSeconds(page);
    const s = await state(page);
    console.log(`skirmish: ${s.fps} fps, ${s.enemies} crusaders standing`);
    expect(s.party.length).toBe(3);
    expect(s.fps).toBeGreaterThanOrEqual(30);
    expect(errors).toEqual([]);
  });

  test('the haven holds 30 frames a second with all five people in view', async ({ page }) => {
    test.setTimeout(120000);
    const errors = await open(page, 'probe=1&fresh=1');
    await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; });
    await talkThrough(page, '1');
    // Álvar walks to the middle of the room, and the camera draws back until all five are in view.
    const box = await page.locator('canvas').boundingBox();
    for (let i = 0; i < 6 && (await state(page)).pos[0] < -1; i++) {
      await page.mouse.click(box.x + box.width * 0.65, box.y + box.height * 0.55);
      await page.waitForTimeout(1000);
    }
    await settle(page);
    const names = ['Malakor', 'Íñigo', 'The captive', 'Zahra', 'Gonzalo'];
    const allInView = (people) => names.every((name) => people[name] && inside(people[name], box));
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    for (let i = 0; i < 8 && !allInView((await state(page)).people); i++) {
      await page.mouse.wheel(0, 100);
      await page.waitForTimeout(400);
    }
    expect(allInView((await state(page)).people)).toBe(true);
    await page.waitForTimeout(3000);
    const fps = (await state(page)).fps;
    console.log(`haven: ${fps} fps`);
    await page.screenshot({ path: `build/e2e/budget-haven-${test.info().project.name}.png` });
    expect(fps).toBeGreaterThanOrEqual(30);
    expect(errors).toEqual([]);
  });
});

test('a first load starts the game in under 20 seconds', async ({ page }) => {
  test.setTimeout(90000);
  // Each test has a fresh browser context, so nothing is cached.
  await page.setViewportSize({ width: 1280, height: 720 });
  const from = Date.now();
  await page.goto('/?probe=1&fresh=1&title=1');
  await page.waitForFunction(() => window.nocturneStarted === true, null, { timeout: 60000, polling: 100 });
  const seconds = (Date.now() - from) / 1000;
  console.log(`first load: ${seconds.toFixed(1)} s`);
  expect(seconds).toBeLessThan(20);
});

test.describe('the frames for the owner', () => {
  test.use({ deviceScaleFactor: 2 });
  fs.mkdirSync('build/e2e', { recursive: true });

  test('the title, the waking and the haven forge', async ({ page }) => {
    test.setTimeout(120000);
    const errors = await open(page, 'probe=1&fresh=1&title=1');
    await page.screenshot({ path: frame('title') });
    await page.keyboard.press('Enter');
    await until(page, () => { window.nocturneProbe(); return window.nocturneState.talking; }, null, 30000);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: frame('waking') });
    await talkThrough(page, '1');
    // To the floor in front of the forge, between Malakor and the smith.
    const people = (await state(page)).people;
    const box = await page.locator('canvas').boundingBox();
    const x = (people['Malakor'][0] + people['Íñigo'][0]) / 2;
    const y = Math.max(people['Malakor'][1], people['Íñigo'][1]) + 60;
    await page.mouse.click(box.x + x, box.y + y);
    await page.waitForTimeout(500);
    await settle(page);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: frame('forge') });
    expect(errors).toEqual([]);
  });

  test('the vault at spawn and the last lock', async ({ page }) => {
    test.setTimeout(120000);
    const errors = await open(page, 'probe=1&fresh=1&at=vault&calm=1');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: frame('vault') });
    const box = await page.locator('canvas').boundingBox();
    for (let i = 0; i < 12; i++) {
      const s = await state(page);
      if (s.notice) break;
      const lock = s.people['LastLock'];
      if (lock && inside(lock, box)) await page.mouse.click(box.x + lock[0], box.y + lock[1]);
      else await page.mouse.click(box.x + box.width * 0.8, box.y + box.height * 0.4);
      await page.waitForTimeout(1500);
    }
    expect((await state(page)).notice).not.toBe('');
    await settle(page);
    await page.screenshot({ path: frame('lock') });
    expect(errors).toEqual([]);
  });

  test('the vault mid-fight and a feed', async ({ page }) => {
    test.setTimeout(180000);
    const errors = await open(page, 'skirmish=1&probe=1');
    const box = await page.locator('canvas').boundingBox();
    const full = (await state(page)).party.map((m) => m.health);
    await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
    await until(page, (from) => {
      window.nocturneProbe();
      return window.nocturneState.party.some((m, k) => m.health < from[k]);
    }, full, 20000);
    await page.waitForTimeout(3000);
    await page.screenshot({ path: frame('fight') });
    // A feed with the mark showing: as soon as a crusader is weak enough to show the mark, the world
    // is paused and Álvar sent to feed on it; then the world is stepped in short paused steps until he
    // is closing in with the mark still showing (it goes when the drinking begins). The last paused
    // frame before it goes is kept.
    const look = () => { window.nocturneProbe(); return window.nocturneState; };
    const setPaused = async (on) => {
      await page.keyboard.press('Space');
      await until(page, (want) => { window.nocturneProbe(); return window.nocturneState.paused === want; }, on);
    };
    let found = false;
    for (let round = 0; round < 10 && !found; round++) {
      const weak = await until(page, () => { window.nocturneProbe(); return window.nocturneState.marked.length > 0; }, null, 5000)
        .then(() => true, () => false);
      if (!weak) {
        await page.mouse.click(box.x + box.width * 0.75, box.y + box.height * 0.5);
        continue;
      }
      await setPaused(true);
      const target = (await page.evaluate(look)).marked[0];
      if (target === undefined || !inside(target, box)) {
        await setPaused(false);
        continue;
      }
      await page.mouse.click(box.x + target[0], box.y + target[1]);
      let last = null;
      for (let step = 0; step < 60; step++) {
        await setPaused(false);
        await page.waitForTimeout(50);
        await setPaused(true);
        const s = await page.evaluate(look);
        if (!s.party[0].feeding || s.marked.length === 0) break;
        last = await page.screenshot();
      }
      if (last !== null) {
        found = true;
        fs.writeFileSync(frame('feed'), last);
      }
      await setPaused(false);
    }
    expect(found).toBe(true);
    expect(errors).toEqual([]);
  });
});
