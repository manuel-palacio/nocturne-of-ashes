// @ts-check
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'e2e',
  webServer: {
    command: 'npx serve -l 8124 --no-clipboard build/web',
    url: 'http://127.0.0.1:8124',
    reuseExistingServer: !process.env.CI,
  },
  use: {
    baseURL: 'http://127.0.0.1:8124',
  },
  projects: [
    // Headed: headless Chromium reads every WebGL frame back through the CPU (or renders with
    // SwiftShader), so it measures the test harness, not the game. Headed runs on the GPU.
    { name: 'chromium', use: { ...devices['Desktop Chrome'], headless: false } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  ],
});
