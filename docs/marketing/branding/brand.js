// Рендер заставок каналов Flak Heaven: node brand.js <папка вывода>
// Использует Playwright (в облаке: /opt/node-tools/node_modules/playwright). Только векторная графика, без кадров игры.
const { chromium } = require(process.env.PW || '/opt/node-tools/node_modules/playwright');
const out = process.argv[2] || '.';
const BG = '#10151c', ACC = '#ffb347', TXT = '#e8edf3', MUT = '#9aa7b6', LINE = '#263241';

// Силуэт самолёта «по мотивам», вид сверху, без опознавательных знаков
const plane = (c) => `<g fill="${c}"><path d="M0,-125 L9,-90 L12,-40 L100,60 L100,82 L14,52 L10,88 L34,106 L34,120 L0,112 L-34,120 L-34,106 L-10,88 L-14,52 L-100,82 L-100,60 L-12,-40 L-9,-90 Z"/></g>`;
const burst = (r, c) => {
  let s = '';
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2, l = r * (i % 2 ? 0.55 : 1);
    s += `<line x1="${Math.cos(a) * r * 0.3}" y1="${Math.sin(a) * r * 0.3}" x2="${Math.cos(a) * l}" y2="${Math.sin(a) * l}" stroke="${c}" stroke-width="${r * 0.035}" stroke-linecap="round"/>`;
  }
  return s;
};
const rings = (n, step, c) => Array.from({ length: n }, (_, i) => `<circle r="${(i + 1) * step}" fill="none" stroke="${c}" stroke-width="2" opacity="${0.5 - i * 0.07}"/>`).join('');

function art(w, h, k, cx = 0.5, cy = 0.5) { // k — масштаб знака; знак в центре
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <defs><radialGradient id="g" cx="50%" cy="50%" r="70%"><stop offset="0" stop-color="#1b2533"/><stop offset="1" stop-color="${BG}"/></radialGradient></defs>
  <rect width="${w}" height="${h}" fill="url(#g)"/>
  <g transform="translate(${w * cx},${h * cy}) scale(${k})">${rings(5, 70, LINE)}<g opacity=".9">${burst(180, ACC)}</g><g transform="rotate(-18)">${plane(TXT)}</g></g></svg>`;
}
const wordmark = (size) => `<div style="font:800 ${size}px 'Inter','Segoe UI',Arial,sans-serif;letter-spacing:.06em;color:${TXT}">FLAK <span style="color:${ACC}">HEAVEN</span></div>`;

const items = [
  ['avatar_1024', 1024, 1024, () => art(1024, 1024, 2.0)], // аватар для Telegram, Max, VK, Discord, YouTube (круг режет края, знак в центре)
  ['vk_cover_1590x400', 1590, 400, () => `<div style="position:relative;width:1590px;height:400px">${art(1590, 400, 0.85, 0.8)}<div style="position:absolute;left:120px;top:0;height:400px;display:flex;flex-direction:column;justify-content:center;gap:12px">${wordmark(84)}<div style="font:500 30px 'Segoe UI',Arial,sans-serif;color:${MUT}">Roguelike про боевую авиацию · вид сверху · вылет 15 минут</div></div></div>`],
  ['discord_banner_960x540', 960, 540, () => `<div style="position:relative;width:960px;height:540px">${art(960, 540, 1.0, 0.5, 0.38)}<div style="position:absolute;left:0;right:0;bottom:50px;display:flex;justify-content:center">${wordmark(64)}</div></div>`],
  ['youtube_banner_2560x1440', 2560, 1440, () => `<div style="position:relative;width:2560px;height:1440px">${art(2560, 1440, 3.2, 0.5, 0.4)}<div style="position:absolute;left:0;right:0;top:1060px;display:flex;flex-direction:column;align-items:center;gap:14px">${wordmark(110)}</div></div>`],
  ['post_cover_1280x720', 1280, 720, () => `<div style="position:relative;width:1280px;height:720px">${art(1280, 720, 2.0, 0.5, 0.55)}<div style="position:absolute;left:70px;top:60px">${wordmark(56)}</div></div>`],
];
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  for (const [n, w, h, f] of items) {
    await p.setViewportSize({ width: w, height: h });
    await p.setContent(`<body style="margin:0;background:${BG}">${f()}</body>`);
    await p.screenshot({ path: `${out}/${n}.png`, clip: { x: 0, y: 0, width: w, height: h } });
  }
  await b.close();
})();
