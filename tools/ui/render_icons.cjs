// Renders the schematic combat-UI icons (modules, skills, wingmen) to transparent PNGs
// for the game: game/art/ui_icons/s_<name>.png, 256×256.
// Source: tools/ui/combat_icons.svg.html (SVG symbols from the combat UI mockup v2,
// approved by Kanta 2026-10-24; filter #vol adds top-left light, specular and cast shadow).
// The glow, frame and family disc are drawn by the game (HudIcons), so one picture serves
// every family colour. Final art comes from thread «Углубить прокачку для демо».
// Run from the repo root: node tools/ui/render_icons.cjs  (needs the preinstalled Playwright)
const { chromium } = require('playwright');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const ROOT = join(__dirname, '..', '..');
const SRC = readFileSync(join(ROOT, 'tools/ui/combat_icons.svg.html'), 'utf8');
const OUT = join(ROOT, 'game/art/ui_icons');
const SIZE = 256;
const names = [...SRC.matchAll(/<symbol id="i-([\w-]+)"/g)].map((m) => m[1]);

(async () => {
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE } });
	for (const n of names) {
		// art sits like in the mockup tile: 78 % of the tile, room for the shadow below
		await page.setContent(`<html><body style="margin:0;background:transparent">${SRC}
			<svg width="${SIZE}" height="${SIZE}" style="overflow:visible">
			<svg x="${SIZE * 0.11}" y="${SIZE * 0.07}" width="${SIZE * 0.78}" height="${SIZE * 0.78}"
				style="overflow:visible;filter:url(#vol)"><use href="#i-${n}"/></svg></svg></body></html>`);
		await page.screenshot({ path: join(OUT, `s_${n}.png`), omitBackground: true });
		console.log('icon', n);
	}
	await browser.close();
})();
