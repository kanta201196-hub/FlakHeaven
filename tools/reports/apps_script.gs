/**
 * Flak Heaven — приём отчётов тестеров.
 * Вариант 1: в Google Таблице: Расширения → Apps Script → заменить весь код этим → Сохранить.
 * Вариант 2 (если вариант 1 не открывается): script.google.com → «Новый проект» → вставить этот код → Сохранить.
 * Работает в обоих вариантах: таблица открывается по SHEET_ID.
 * Затем: Начать развертывание → Новое развертывание → тип «Веб-приложение»,
 *        «Выполнять от имени»: Я, «У кого есть доступ»: Все → Развернуть → скопировать URL (…/exec).
 */

const SHEET_ID = '1SYwhNWxzcdHOwwxqwPBZiOK3edZtQUk-fbXLQL8CbPw'; // таблица «Flak Heaven — отчёты тестеров»
const TOKEN = 'fh-tester-2026';          // должен совпадать с игрой (защита от случайного мусора)
const RUN_TOKEN = 'fh-run-2026';         // 3.5: строка лога каждого вылета, без анкеты → лист «Вылеты»
const MAX_CELL = 45000;                  // лимит ячейки Google Таблиц — 50 000 символов

const REPORT_COLS = [
  'Получен', 'Сборка', 'Тестер', 'Отправлен из игры', 'Класс', 'Итог', 'Время вылета, с', 'Уровень', 'Сбито',
  'Связки', 'Оценка 1–5', 'Сыграть ещё?', 'Скучно / раздражало', 'Непонятно', 'Комментарий / баги',
  'ОС', 'Видеокарта', 'Экран', 'FPS средн.', 'ID отчёта',
  'Картинка / камера / пули / тормоза',  // с 3.4; строка «Короткие ответы» (с 3.5 — все ответы кнопками)
  // с 3.5 (после теста 3.5-s7): новые вопросы; заголовки в старой таблице допишутся сами
  'Почему вышли раньше', 'Сложность', 'Темп', 'Выбор улучшений', 'Звук 1–5', 'Понравилось'
];
const RUN_COLS = ['Получен', 'Сборка', 'Тестер', 'Отправлен из игры', 'ОС', 'Видеокарта', 'Экран', 'Строка лога вылета', 'Заголовок лога'];
const LOG_COLS = ['ID отчёта', 'Сборка', 'Тестер', 'Заголовок лога', 'Строка лога вылета', 'Хвост журнала Godot'];

function sheet_(name, cols) {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  let sh = ss.getSheetByName(name);
  if (!sh && name === 'Отчёты') {
    // первый лист с заголовками уже создан вместе с таблицей — просто переименуем его
    const first = ss.getSheets()[0];
    if (String(first.getRange(1, 1).getValue()) === 'Получен') {
      first.setName(name);
      sh = first;
    }
  }
  if (!sh) {
    sh = ss.insertSheet(name);
  }
  if (sh.getLastRow() === 0) {
    sh.appendRow(cols);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, cols.length).setFontWeight('bold');
  } else if (sh.getLastColumn() < cols.length) {
    // новые колонки в новой версии скрипта — дописываем заголовки справа
    const from = sh.getLastColumn() + 1;
    sh.getRange(1, from, 1, cols.length - from + 1).setValues([cols.slice(from - 1)]).setFontWeight('bold');
  }
  return sh;
}

function cut_(v) {
  const s = v === undefined || v === null ? '' : String(v);
  return s.length > MAX_CELL ? s.substring(s.length - MAX_CELL) : s;
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const d = JSON.parse(e.postData.contents);
    if (d.token === RUN_TOKEN && d.kind === 'run') {
      sheet_('Вылеты', RUN_COLS).appendRow([
        new Date(), d.build, d.tester, d.sent_at, d.os, d.gpu, d.screen, cut_(d.run_row), cut_(d.run_header)
      ]);
      return ContentService.createTextOutput('ok run');
    }
    if (d.token !== TOKEN) {
      return ContentService.createTextOutput('bad token');
    }
    const id = Utilities.getUuid().substring(0, 8);
    sheet_('Отчёты', REPORT_COLS).appendRow([
      new Date(), d.build, d.tester, d.sent_at, d.cls, d.outcome, d.run_seconds, d.level, d.kills,
      d.synergies, d.rating, d.again, cut_(d.boring), cut_(d.unclear), cut_(d.comment),
      d.os, d.gpu, d.screen, d.fps, id, d.visual,
      d.why, d.diff, d.pace, d.cards, d.sound, cut_(d.liked)
    ].map(v => (typeof v === 'string' ? cut_(v) : v)));
    sheet_('Логи', LOG_COLS).appendRow([id, d.build, d.tester, cut_(d.run_header), cut_(d.run_row), cut_(d.log_tail)]);
    return ContentService.createTextOutput('ok ' + id);
  } catch (err) {
    return ContentService.createTextOutput('error ' + err);
  } finally {
    lock.releaseLock();
  }
}

function doGet() {
  return ContentService.createTextOutput('Flak Heaven reports: ok');
}
