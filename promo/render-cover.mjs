import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('C:\\Users\\Admin1\\.dsh\\profiles\\desktop\\node_modules\\playwright');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const W = 1146, H = 717, SCALE = 2;

const browser = await chromium.launch({ executablePath: EDGE, headless: true });
const page = await browser.newPage({
  viewport: { width: W, height: H },
  deviceScaleFactor: SCALE,
});
await page.goto('file:///' + path.join(__dirname, 'cover.html').replace(/\\/g, '/'));
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(800);
await page.screenshot({ path: path.join(__dirname, 'cover.png') });
await browser.close();
console.log(`cover.png ${W * SCALE}x${H * SCALE}`);
