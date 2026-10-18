// Картинки к постам: node posts.js <папка вывода> <папка с кадрами>. Кадры без интерфейса, поверх только название.
const { chromium } = require(process.env.PW || '/opt/node-tools/node_modules/playwright');
const fs = require('fs');
const out = process.argv[2] || '.', src = process.argv[3] || '/mnt/project-files/visual';
const ACC = '#ffb347', TXT = '#e8edf3';
const bar = (title, sub) => `<div style="position:absolute;left:0;right:0;bottom:0;padding:90px 56px 40px;background:linear-gradient(transparent,rgba(10,14,20,.88));font-family:Inter,'Segoe UI',Arial,sans-serif">
<div style="font-weight:800;font-size:58px;letter-spacing:.05em;color:${TXT}">${title}</div>${sub ? `<div style="margin-top:8px;font-size:30px;color:#c6d0db">${sub}</div>` : ''}</div>`;
const items = [
  ['series4_proto3_late', null, 'Прототип 3, поздняя версия', 'Скалы с текстурой, у самолётов тени, штурмовик с НАР', '/mnt/project-files/marketing/content/img/src/proto3_late.png'],
  ['series3_proto3', null, 'Прототип 3: первое 3D', 'Скала поднимается над землёй, у самолётов тени', '/mnt/project-files/marketing/content/img/src/proto3_rock.png'],
  ['series3b_cards', null, 'Прототип 3', 'Новый уровень: выбираешь одну из четырёх карточек', '/mnt/project-files/marketing/content/img/src/proto3_cards.png'],
  ['series2_proto2', null, 'Прототип 2', 'Вместо фигур — картинки: самолёты, дома, земля', '/mnt/project-files/marketing/content/img/src/proto2.png'],
  ['series1_proto1', null, 'Прототип 1', 'Самолёт — треугольник, враги — ромбы', '/mnt/project-files/marketing/content/img/src/proto1.png'],
  ['post1_about', 's4b_biome_river_village_t28_after.png', `FLAK <span style="color:${ACC}">HEAVEN</span>`, 'Roguelike про боевую авиацию'],
  ['post2_testers', 's4b_biome_scene_tank_t28_after.png', 'Ищу тестеров', 'Windows и Mac · 30–60 минут · flakheaven.com'],
];
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  for (const [n, f, t, s, abs] of items) {
    await p.setContent(`<body style="margin:0"><div style="position:relative;width:1280px;height:720px;overflow:hidden"><img src="data:image/png;base64,${fs.readFileSync(abs || `${src}/${f}`).toString('base64')}" style="width:1280px;height:720px;object-fit:cover">${bar(t, s)}</div></body>`);
    await p.waitForLoadState('load'); await p.waitForTimeout(300);
    await p.screenshot({ path: `${out}/${n}.png` });
  }
  await b.close();
})();

// Было / стало: node posts.js <папка вывода> <папка кадров> делает и пары ниже (запуск тем же скриптом)
const pairs = [
  ['bs_proto1_now', '/mnt/project-files/marketing/content/img/src/proto1.png', '/mnt/project-files/marketing/content/img/src/now_3_5.png', 'Прототип 1', 'Сборка 3.5'],
  ['bs_explosions', '/mnt/project-files/marketing/content/img/src/explosions_before.png', '/mnt/project-files/marketing/content/img/src/explosions_now.png', 'вспышка', 'дым и воронки'],
  ['bs_clouds', '/mnt/project-files/marketing/content/img/src/clouds_before.png', '/mnt/project-files/marketing/content/img/src/clouds_after.png', 'дымка', 'облака'],
];
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const img = (f) => `data:image/png;base64,${fs.readFileSync(f).toString('base64')}`;
  const half = (f, label, c) => `<div style="width:622px"><img src="${img(f)}" style="width:622px;height:350px;object-fit:cover;display:block;border-radius:6px"><div style="margin-top:22px;text-align:center;font:800 50px Inter,'Segoe UI',Arial,sans-serif;color:${c}">${label}</div></div>`;
  for (const [n, a, bb, la, lb] of pairs) {
    await p.setContent(`<body style="margin:0;background:#10151c"><div style="display:flex;gap:16px;width:1280px;height:720px;box-sizing:border-box;padding:140px 16px 0"><!-- рамка -->${half(a, 'Было: ' + la, TXT)}${half(bb, 'Стало: ' + lb, ACC)}</div></body>`);
    await p.waitForTimeout(300);
    await p.screenshot({ path: `${out}/${n}.png` });
  }
  await b.close();
})();
