// e2e/language.spec.js
// The game in Spanish on the built game: `?lang=es` plays the waking, a choice at the captive and
// Íñigo in Spanish, read from the box; a Spanish browser gets Spanish with no parameter, and `?lang=en`
// forces English over it. Then the frames in Spanish for the owner, from Chromium only
// (build/shots/es-<frame>.png): the title and its question, the controls card, the waking, Íñigo, the
// captive's choices, Zahra's longest line, Malakor's letter, the vault's hints, the closing card, and
// the longest line, the title, the controls and the closing card again at 800 × 500; then, in a fight
// played badly, the Rites and door hints a good one does not bring.
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const { state, open, until, talkThrough, use, fightAsThePlayer } = require('./helpers');

// The hints, by the English text the probe reports, and the name of each one's frame.
const HINTS = {
  'Space pauses the fight: give your orders, then let it run.': 'pause',
  '1: Iron Sinew, to strike harder. 2: Baleful Eye, then click a foe to still him.': 'rites',
  'The helmed sergeants hit hardest. Still one with Baleful Eye, and drink when he weakens.': 'sergeant',
  'Click a weakened foe to feed: it restores Blood and mends wounds.': 'feed',
  '%s is running dry. Feed, or the Fury will choose for you.': 'dry',
  'The Fury has %s. It ends when the hunger is fed or burns out.': 'fury',
  'The west door is a way out. The guard will close ranks again.': 'door',
};

const talking = () => { window.nocturneProbe(); return window.nocturneState.talking; };

// Presses Enter until the line on show is `line`, within the conversation on show.
async function enterUntil(page, line) {
  for (let i = 0; i < 20; i++) {
    const s = await state(page);
    if (s.line === line) return s;
    if (!s.talking || s.choices.length > 0) break;
    await page.keyboard.press('Enter');
    await page.waitForTimeout(250);
  }
  expect((await state(page)).line).toBe(line);
  return state(page);
}

test('the waking, a choice at the captive and Íñigo, in Spanish on request', async ({ page }) => {
  test.setTimeout(180000);
  const errors = await open(page, 'probe=1&fresh=1&calm=1&lang=es');
  await until(page, talking, null, 30000);
  let s = await state(page);
  expect([s.speaker_name, s.line]).toEqual(['Malakor', 'Despiertas. Bien. No todos despiertan.']);
  await enterUntil(page, 'Elena. ¿Dónde está?');
  await talkThrough(page, '1');

  await use(page, 'The captive', (t) => t.talking);
  s = await enterUntil(page, 'Tengo la pierna rota, y tengo sed, y no te tengo miedo. Haz lo que has venido a hacer.');
  expect(s.speaker).toBe('The captive');
  expect(s.speaker_name).toBe('El cautivo');
  expect(s.choices).toEqual(['Beber un poco', 'Desangrarlo', 'Dejarlo en paz']);
  await page.keyboard.press('1');
  await page.waitForTimeout(250);
  expect((await state(page)).line).toBe('Has parado. ¿Por qué has parado?');
  await talkThrough(page, '1');
  expect((await state(page)).flags).toEqual(expect.arrayContaining(['captive_done']));

  await use(page, 'Íñigo', (t) => t.talking);
  s = await state(page);
  expect([s.speaker_name, s.line]).toEqual(['Íñigo',
    'Apártate de la pila del temple. Has estado en la celda, se te nota. Él me mandó que te contara cómo son aquí las cosas.']);
  await enterUntil(page, 'Y el Silencio: los vivos de arriba no deben saber nunca lo que camina bajo sus pies. Eso es todo. Al salir, pásame las tenazas.');
  await talkThrough(page, '1');
  expect((await state(page)).flags).toEqual(expect.arrayContaining(['smith_heard']));
  expect(errors).toEqual([]);
});

test.describe('a browser set to Spanish', () => {
  test.use({ locale: 'es-ES' });

  test('gets Spanish with no parameter, and English with ?lang=en', async ({ page }) => {
    test.setTimeout(120000);
    let errors = await open(page, 'probe=1&fresh=1');
    await until(page, talking, null, 30000);
    expect((await state(page)).line).toBe('Despiertas. Bien. No todos despiertan.');
    expect(errors).toEqual([]);
    errors = await open(page, 'probe=1&fresh=1&lang=en');
    await until(page, talking, null, 30000);
    expect((await state(page)).line).toBe('You wake. Good. Not all of them do.');
    expect(errors).toEqual([]);
  });
});

test.describe('the frames in Spanish', () => {
  test.use({ deviceScaleFactor: 2 });

  test('every text a player reads, at 1280 × 720 and at 800 × 500', async ({ page }) => {
    test.skip(test.info().project.name !== 'chromium', 'the frames come from Chromium');
    test.setTimeout(600000);
    fs.mkdirSync('build/shots', { recursive: true });
    const shot = (name) => page.screenshot({ path: `build/shots/es-${name}.png` });
    // Sets the page's size and waits for the game to lay itself out again.
    const size = async (width, height) => {
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(800);
    };
    // Clicks the controls button, 36 px in from the bottom right at 1280 × 720, wherever it is now.
    const openControls = async () => {
      const box = await page.locator('canvas').boundingBox();
      const k = Math.min(box.width / 1280, box.height / 720);
      await page.mouse.click(box.x + box.width - 36 * k, box.y + box.height - 36 * k);
      await page.waitForTimeout(600);
    };

    const errors = await open(page, 'probe=1&fresh=1&title=1&calm=1&lang=es');
    await shot('title');
    await size(800, 500);
    await shot('title-800x500');
    await size(1280, 720);

    await page.keyboard.press('Enter');
    await until(page, talking, null, 30000);
    await page.waitForTimeout(1500);
    await shot('waking');
    await talkThrough(page, '1');

    await openControls();
    await shot('controls');
    await size(800, 500);
    await shot('controls-800x500');
    await page.keyboard.press('Escape');
    await size(1280, 720);

    await use(page, 'Íñigo', (t) => t.talking);
    await page.waitForTimeout(500);
    await shot('inigo');
    const longest = 'Y el Silencio: los vivos de arriba no deben saber nunca lo que camina bajo sus pies. Eso es todo. Al salir, pásame las tenazas.';
    await enterUntil(page, longest);
    await shot('longest');
    await size(800, 500);
    await shot('longest-800x500');
    await size(1280, 720);
    await talkThrough(page, '1');

    await use(page, 'The captive', (t) => t.talking);
    await enterUntil(page, 'Tengo la pierna rota, y tengo sed, y no te tengo miedo. Haz lo que has venido a hacer.');
    await shot('captive-choices');
    await size(800, 500);
    await shot('captive-choices-800x500');
    await size(1280, 720);
    await talkThrough(page, '3');

    await use(page, 'Zahra', (t) => t.talking);
    await enterUntil(page, '¿Lo sientes detrás de los ojos? Sostén así la mirada de un hombre y olvidará cómo moverse.');
    await shot('zahra');
    await talkThrough(page, '1');
    await page.waitForTimeout(500);
    await use(page, 'Gonzalo', (t) => t.talking);
    await talkThrough(page, '1');
    await page.waitForTimeout(800);

    await use(page, 'Malakor', (t) => t.talking);
    for (let i = 0; i < 10 && (await state(page)).choices.length === 0; i++) {
      await page.keyboard.press('Enter');
      await page.waitForTimeout(250);
    }
    expect((await state(page)).choices).toEqual(['Entregársela', 'Decir que ardió en el barrio']);
    await shot('letter');
    await talkThrough(page, '2');

    // Down to the vault, fought to cleared, each hint kept as it first shows.
    await use(page, 'StairDoor', (t) => t.room === 'vault');
    await page.waitForTimeout(1500);
    const seen = new Set();
    for (let round = 0; round < 150; round++) {
      const s = await state(page);
      const hint = HINTS[s.notice];
      if (hint && !seen.has(hint)) {
        seen.add(hint);
        await shot(`hint-${hint}`);
        if (seen.size === 1) {
          await size(800, 500);
          await shot(`hint-${hint}-800x500`);
          await size(1280, 720);
        }
      }
      if (s.cleared || s.fallen) break;
      await fightAsThePlayer(page, 1);
    }
    console.log(`hints seen: ${[...seen].join(', ')}`);
    expect((await state(page)).cleared).toBe(true);
    await until(page, () => { window.nocturneProbe(); return window.nocturneState.closing_ready; });
    await page.waitForTimeout(500);
    await shot('closing');
    await size(800, 500);
    await shot('closing-800x500');
    await size(1280, 720);
    await page.keyboard.press('Enter');

    // The title again, with the save: Continue, and New game's question.
    await open(page, 'probe=1&title=1&lang=es');
    const t = await state(page);
    const box = await page.locator('canvas').boundingBox();
    await page.mouse.click(box.x + t.new_game[0], box.y + t.new_game[1]);
    await page.waitForTimeout(800);
    expect((await state(page)).asking).toBe(true);
    await shot('title-question');
    await size(800, 500);
    await shot('title-question-800x500');
    expect(errors).toEqual([]);
  });

  test('the hints the first fight did not bring: the Rites and the door', async ({ page }) => {
    test.skip(test.info().project.name !== 'chromium', 'the frames come from Chromium');
    test.setTimeout(240000);
    fs.mkdirSync('build/shots', { recursive: true });
    // The guard fights back; Álvar strikes without the Rites until their hint has shown, then spends
    // his Blood on Iron Sinew whenever it is off and never feeds. The Fury hint is not looked for here:
    // it rarely comes before Álvar falls; tests/story/test_hints.gd checks that it fits, in Spanish too.
    const errors = await open(page, 'probe=1&fresh=1&at=vault&lang=es');
    const box = await page.locator('canvas').boundingBox();
    const seen = new Set();
    for (let round = 0; round < 120 && seen.size < 2; round++) {
      const s = await state(page);
      const hint = HINTS[s.notice];
      if (['rites', 'door'].includes(hint) && !seen.has(hint)) {
        seen.add(hint);
        await page.screenshot({ path: `build/shots/es-hint-${hint}.png` });
      }
      if (s.fallen || s.cleared) break;
      const alvar = s.party[0];
      if (seen.has('rites') && !alvar.effects.includes('iron_sinew')) await page.keyboard.press('1');
      const foe = s.foes[0];
      if (foe) await page.mouse.click(box.x + Math.min(Math.max(foe[0], 300), s.view[0] - 80), box.y + Math.min(Math.max(foe[1], 320), s.view[1] - 80));
      await page.waitForTimeout(800);
    }
    console.log(`hints seen: ${[...seen].join(', ')}`);
    expect(seen.has('rites')).toBe(true);
    expect(errors).toEqual([]);
  });
});
