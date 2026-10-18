// Создаёт Google Форму «Flak Heaven — заявка тестера» и таблицу ответов.
// Как запустить: script.google.com → «Новый проект» → вставить этот файл → выбрать функцию createApplicantForm → «Выполнить» → разрешить доступ.
// В журнале выполнения появятся ссылки на форму (для кнопки «Стать тестером» на flakheaven.com) и на таблицу.
function createApplicantForm() {
  var form = FormApp.create('Flak Heaven — заявка тестера');
  form.setDescription('Тестовые сборки Flak Heaven для Windows и Mac. Нужно 30–60 минут, 3–5 вылетов и честный отзыв. Имя и контакт используем только чтобы прислать сборку. Сайт: https://flakheaven.com');
  form.setCollectEmail(false);
  form.addTextItem().setTitle('Как к вам обращаться (имя в сети)').setRequired(true);
  form.addTextItem().setTitle('Контакт: Telegram @ник или почта').setRequired(true);
  form.addMultipleChoiceItem().setTitle('Система').setChoiceValues(['Windows 10/11', 'macOS (Apple M)', 'macOS (Intel)', 'Другая']).setRequired(true);
  form.addTextItem().setTitle('Видеокарта и процессор (если знаете)');
  form.addMultipleChoiceItem().setTitle('Сколько часов в неделю играете').setChoiceValues(['до 5', '5–15', 'больше 15']);
  form.addCheckboxItem().setTitle('Какие игры любите').setChoiceValues(['roguelike', 'Vampire Survivors и похожие', 'аркадные шутеры', 'авиасимы', 'почти не играю в такое']);
  form.addMultipleChoiceItem().setTitle('Откуда узнали о нас').setChoiceValues(['Telegram', 'Max', 'VK', 'Discord', 'Reddit', 'друг', 'сайт', 'другое']);
  form.addCheckboxItem().setTitle('Согласие').setChoiceValues(['Согласен получить тестовую сборку и отправлять отчёты о ней']).setRequired(true);
  var ss = SpreadsheetApp.create('Flak Heaven — заявки тестеров');
  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());
  Logger.log('Форма (для ответов): ' + form.getPublishedUrl());
  Logger.log('Форма (редактирование): ' + form.getEditUrl());
  Logger.log('Таблица: ' + ss.getUrl());
}
