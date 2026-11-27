// e2e/look.spec.js
// The browser budget: frame rate with everyone on screen, the time a first load takes, and the frames
// the owner is shown (build/e2e/look-<frame>-<browser>.png, 1280 × 720 at twice the pixel density).
const { test, expect } = require('@playwright/test');
const { state, open, until, talkThrough, use, fightAsThePlayer } = require('./helpers');
const fs = require('fs');

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

// The frame rate of each of the next `seconds` seconds.
async function rates(page, seconds) {
  const found = [];
  for (let i = 0; i < seconds; i++) {
    await page.waitForTimeout(1000);
    found.push((await state(page)).fps);
  }
  return found;
}

test.describe('the frame rate with everyone on screen', () => {
  test('the skirmish holds 30 frames a second with the party and six crusaders fighting', async ({ page }) => {
    test.setTimeout(120000);
    const errors = await open(page, 'skirmish=1&probe=1');
    const box = await page.locator('canvas').boundingBox();
    // The camera drawn back as far as it goes, so that both groups of crusaders (x ≈ 1 and x ≈ 9)
    // fit on screen with the party.
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    for (let i = 0; i < 6; i++) {
      await page.mouse.wheel(0, 100);
      await page.waitForTimeout(100);
    }
    // Álvar, quickened by Iron Sinew, runs east past the first group to between the two, so that
    // all six come at the party while all six still stand.
    const full = (await state(page)).party.map((m) => m.health);
    await page.keyboard.press('1');
    for (let i = 0; i < 15 && (await state(page)).pos[0] < 3; i++) {
      await page.mouse.click(box.x + box.width * 0.9, box.y + box.height * 0.5);
      await page.waitForTimeout(400);
    }
    // The fight's window starts at the first blow with all six standing and on screen.
    await until(page, (from) => {
      window.nocturneProbe();
      const s = window.nocturneState;
      const view = s.view;
      const onScreen = s.foes.filter((p) => p[0] > 0 && p[0] < view[0] && p[1] > 0 && p[1] < view[1]);
      return s.party.some((m, k) => m.health < from[k]) && s.enemies === 6 && onScreen.length === 6;
    }, full, 20000);
    await page.screenshot({ path: `build/e2e/budget-skirmish-${test.info().project.name}.png` });
    const fighting = await rates(page, 10);
    const end = await state(page);
    console.log(`fighting, frames a second: ${fighting.join(' ')}; ${end.enemies} crusaders standing at the end`);
    expect(end.party.length).toBe(3);
    expect(Math.min(...fighting)).toBeGreaterThanOrEqual(30);
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
    await page.waitForTimeout(1000);
    const seconds = await rates(page, 5);
    console.log(`haven, frames a second: ${seconds.join(' ')}`);
    await page.screenshot({ path: `build/e2e/budget-haven-${test.info().project.name}.png` });
    expect(allInView((await state(page)).people)).toBe(true);
    expect(Math.min(...seconds)).toBeGreaterThanOrEqual(30);
    expect(errors).toEqual([]);
  });
});

// The moment, in the page's own clock (milliseconds since navigation), that `fn` first held there:
// taken inside the page, so a main thread held by the engine cannot shift it.
async function pageTimeWhen(page, fn, timeout) {
  await page.waitForFunction(`(() => {
    if (!(${fn})()) return false;
    window.__heldAt = window.__heldAt || performance.now();
    return true;
  })()`, null, { timeout, polling: 50 });
  const at = await page.evaluate(() => { const t = window.__heldAt; window.__heldAt = undefined; return t; });
  return at;
}

const answers = () => {
  if (window.nocturneStarted !== true) return false;
  window.nocturneProbe();
  return window.nocturneState !== undefined;
};

test('a first load has the title answering in under 20 seconds', { tag: '@alone' }, async ({ page }) => {
  test.setTimeout(90000);
  // Each test has a fresh browser context, so nothing is cached.
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?probe=1&fresh=1&title=1');
  const at = await pageTimeWhen(page, answers.toString(), 60000);
  console.log(`first load: the title answers at ${(at / 1000).toFixed(1)} s`);
  expect((await state(page)).title).toBe(true);
  expect(at).toBeLessThan(20000);
});

test('New game pressed as soon as the title answers reaches the haven within 15 s of the page opening', { tag: '@alone' }, async ({ page }) => {
  test.setTimeout(90000);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/?probe=1&fresh=1&title=1');
  const answered = await pageTimeWhen(page, answers.toString(), 60000);
  await page.keyboard.press('Enter');
  const haven = await pageTimeWhen(page, (() => {
    window.nocturneProbe();
    const s = window.nocturneState;
    return !s.title && s.room === 'haven';
  }).toString(), 30000);
  console.log(`title answers at ${(answered / 1000).toFixed(1)} s; the haven at ${(haven / 1000).toFixed(1)} s`);
  expect(haven).toBeLessThan(15000);
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

  test('the vault at spawn, the closing card and the last lock', async ({ page }) => {
    test.setTimeout(300000);
    const errors = await open(page, 'probe=1&fresh=1&at=vault&calm=1');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: frame('vault') });
    // The vault fought to cleared, `calm=1` keeping the crusaders still, played with the Blood: Iron
    // Sinew, feeds on the marked, blows at the rest. Then the closing card, which says the story rests here.
    await fightAsThePlayer(page, 150);
    expect((await state(page)).cleared).toBe(true);
    await until(page, () => { window.nocturneProbe(); return window.nocturneState.closing_ready; });
    await page.waitForTimeout(500);
    await page.screenshot({ path: frame('closing') });
    // The card closed, the last lock tried: it does not yield, and says where the story rests.
    await page.keyboard.press('Enter');
    await until(page, () => { window.nocturneProbe(); return !window.nocturneState.closing; });
    const line = 'The last lock does not yield. This is where the story rests, for now.';
    await use(page, 'LastLock', (t) => t.notice === line);
    await settle(page);
    expect((await state(page)).notice).toBe(line);
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
    // is paused and Álvar sent to feed on it; then the world is stepped in short paused steps while he
    // is closing in with the mark still showing (it goes when the drinking begins). The last paused
    // frame before it goes is kept, the frame of the order itself when the drinking begins at once.
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
      // On the web a click is taken at the end of its frame (so a key pressed with it goes first): the
      // order shows a frame later.
      await until(page, () => { window.nocturneProbe(); return window.nocturneState.party[0].feeding; }, null, 1000)
        .catch(() => {});
      // The paused frame of the order itself: often the meal is the enemy he is already striking, and
      // the drinking begins within the first step.
      const ordered = await page.evaluate(look);
      let last = ordered.party[0].feeding && ordered.marked.length > 0 ? await page.screenshot() : null;
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
