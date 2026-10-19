# Сайт Flak Heaven

Одна страница `index.html` без внешних зависимостей, два языка (RU/EN). Всё лежит здесь же: шрифты `fonts/` (SIL OFL), 3D-просмотрщик `js/model-viewer.min.js` (model-viewer 3.5.0, Apache 2.0), модели `models/` (сжатые копии ангарных моделей: `gltf-transform optimize --compress quantize --texture-compress webp --texture-size 1024`), видео `video/` (5–8 с, 960×390, из нарезок `marketing/clips/final`, без звука, без HUD и боссов), музыка меню `audio/menu.mp3` (играет только по кнопке «Звук»). Модели и видео грузятся, только когда блок подходит к экрану. Ссылки на форму тестера, Steam и соцсети — в `LINKS` в конце файла: пока адрес пустой, кнопка скрыта.

Публикация (бесплатно): Cloudflare Pages, подключить репозиторий, папка вывода `site`, сборка не нужна. Подробные шаги — в треде «Маркетинг и реклама». Скриншоты добавляем после чистки кадров и запуска Архипелага.

## Адрес и публикация (18.10.2026)
Сайт открыт на https://flakheaven.com (и www). Домен куплен у reg.ru, DNS в Cloudflare, проект Cloudflare Pages `flakheaven` берёт папку `site` из ветки `main` и обновляется сам при каждом слиянии. Запасной адрес: https://flakheaven.pages.dev.
