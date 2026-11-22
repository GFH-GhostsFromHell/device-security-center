/**
 * Generate safe, reproducible screenshots from the checked-in web interface.
 * No production account, server data, encryption keys, or credentials are used.
 *
 * Run via .github/workflows/capture-readme-screenshots.yml.
 * Serves the original HTML locally, with an empty status API response.
 * Screenshots represent the web layout only, not a live authenticated session.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const output = path.resolve(__dirname, '../docs/screenshots');
const base = 'http://127.0.0.1:8765/device-security.html';

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: 1360, height: 860 },
      deviceScaleFactor: 1,
      reducedMotion: 'reduce',
      colorScheme: 'light'
    });

    // Read-only, unauthenticated preview. Avoid backend requests and private data.
    await page.route('**/api/zt01/devices', route =>
      route.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
    await page.route('**/api/zt01/**', route =>
      route.fulfill({ status: 401, contentType: 'application/json', body: '{}' }));
    // The actual UI layout is fully in HTML; prevent account API requests.
    await page.route('**/device-security-chat.js*', route => route.abort());
    await page.route('**/device-security-escrow.js*', route => route.abort());

    const res = await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 30000 });
    if (!res || !res.ok()) throw Error('Web UI did not load at ' + base);
    await page.waitForTimeout(450);

    const shots = [
      { file: 'web-device-status.png', selector: '#devicesTitle', name: 'Device status' },
      { file: 'web-recovery-requests.png', selector: '#escrowTitle', name: 'Encrypted recovery backups' },
      { file: 'web-encrypted-chat.png', selector: '#supportTitle', name: 'Encrypted support chat' }
    ];

    for (const shot of shots) {
      if (shot.selector !== '#devicesTitle') {
        await page.locator(shot.selector).scrollIntoViewIfNeeded();
        await page.evaluate((selector) => {
          const node = document.querySelector(selector);
          if (node) window.scrollBy(0, -85);
        }, shot.selector);
        await page.waitForTimeout(200);
      }
      await page.screenshot({
        path: path.join(output, shot.file),
        animations: 'disabled',
        fullPage: false
      });
      console.log('Saved ' + shot.file + ' (' + shot.name + ')');
    }
    await page.close();
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
