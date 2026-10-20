# Сайт Flak Heaven

Одна страница `index.html` без внешних зависимостей, два языка (RU/EN). Всё лежит здесь же: шрифты `fonts/` (SIL OFL), 3D-просмотрщик `js/model-viewer.min.js` (model-viewer 3.5.0, Apache 2.0), модели `models/` (сжатые копии ангарных моделей: `gltf-transform optimize --compress quantize --texture-compress webp --texture-size 1024`), видео `video/` (5–8 с, 960×390, из нарезок `marketing/clips/final`, без звука, без HUD и боссов), музыка меню `audio/menu.mp3` (играет только по кнопке «Звук»). Модели и видео грузятся, только когда блок подходит к экрану. Ссылки на форму тестера, Steam и соцсети — в `LINKS` в конце файла: пока адрес пустой, кнопка скрыта.

Публикация (бесплатно): Cloudflare Pages, подключить репозиторий, папка вывода `site`, сборка не нужна. Подробные шаги — в треде «Маркетинг и реклама». Скриншоты добавляем после чистки кадров и запуска Архипелага.

## Адрес и публикация (18.10.2026)
Сайт открыт на https://flakheaven.com (и www). Домен куплен у reg.ru, DNS в Cloudflare, проект Cloudflare Pages `flakheaven` берёт папку `site` из ветки `main` и обновляется сам при каждом слиянии. Запасной адрес: https://flakheaven.pages.dev.

Модели и видео кэшируются браузером на час. Если меняете модель или ролик, давайте файлу новое имя (`bomber_v2.glb`), иначе у тех, кто уже открывал сайт, останется старый.

## Поиск и превью ссылок (20.10.2026)
- Превью ссылки в Telegram, VK и др. — теги `og:*` и `twitter:*` в `index.html`, картинка `img/og_v2.jpg` (1200×630). Меняете картинку — новое имя файла: Telegram и VK долго помнят старую.
- Описание игры для поисковиков — блок `application/ld+json` (VideoGame) там же.
- `robots.txt` разрешает всё и указывает на `sitemap.xml`. Новая страница → строка в `sitemap.xml`.
- IndexNow (Яндекс, Bing и др. без аккаунта): ключ — файл `548049779593c0a736e35c57e02455ff.txt`. После слияния изменений сайта:
  `curl -s -X POST https://yandex.com/indexnow -H 'Content-Type: application/json' -d '{"host":"flakheaven.com","key":"548049779593c0a736e35c57e02455ff","keyLocation":"https://flakheaven.com/548049779593c0a736e35c57e02455ff.txt","urlList":["https://flakheaven.com/","https://flakheaven.com/privacy.html"]}'`
  (то же на `https://api.indexnow.org/indexnow`). Ответ 200 или 202 — принято.
- Яндекс Вебмастер и Google Search Console требуют аккаунта владельца — подключает Kanta.
