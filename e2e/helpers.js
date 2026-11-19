// e2e/helpers.js
// What the browser tests share: opening the game with the probe, reading its state, waiting on it and
// talking through a conversation.

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

module.exports = { state, open, until, talkThrough };
