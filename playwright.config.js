// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'e2e',
  // The test flavour (build/web) for every test but public.spec.js, which reads the public flavour
  // (build/public, `ops/build-web.sh public`), the site's, on a port of its own.
  webServer: [
    {
      command: 'npx serve -l 8124 --no-clipboard build/web',
      url: 'http://127.0.0.1:8124',
      reuseExistingServer: !process.env.CI,
    },
    {
      command: 'npx serve -l 8125 --no-clipboard build/public',
      url: 'http://127.0.0.1:8125',
      reuseExistingServer: !process.env.CI,
    },
  ],
  use: {
    baseURL: 'http://127.0.0.1:8124',
    // The game picks its language from the browser; the tests read the English texts.
    locale: 'en-US',
  },
  projects: [
    // Headed: headless Chromium reads every WebGL frame back through the CPU (or renders with
    // SwiftShader), so it measures the test harness, not the game. Headed runs on the GPU.
    { name: 'chromium', use: { ...devices['Desktop Chrome'], headless: false }, testIgnore: /public\.spec\.js/ },
    // Tests tagged @alone time the page's load, which another browser rendering beside it slows: in
    // Firefox they run in a project of their own, after the others are done.
    { name: 'firefox', use: { ...devices['Desktop Firefox'] }, grepInvert: /@alone/, testIgnore: /public\.spec\.js/ },
    {
      name: 'firefox-alone',
      use: { ...devices['Desktop Firefox'] },
      grep: /@alone/,
      testIgnore: /public\.spec\.js/,
      dependencies: ['chromium', 'firefox'],
    },
    // The public flavour, in Chromium only.
    {
      name: 'public',
      testMatch: /public\.spec\.js/,
      use: { ...devices['Desktop Chrome'], headless: false, baseURL: 'http://127.0.0.1:8125' },
    },
  ],
});
