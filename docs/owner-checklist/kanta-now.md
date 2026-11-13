# Только Kanta: что не может сделать Claude

Обновлено: 13.11.2026

Первый пункт каждой планёрки (решение Kanta 22.10.2026, ревью 5.7). Не больше 7 пунктов. Планёрка показывает, сколько дней до срока. Сделанное — вычёркивать и переносить в `checklist.md` с датой.

Дни до срока считаются от 13.11.2026. Всё, что не подтверждено сообщением Kanta или документом, помечено как догадка.

| № | Что | Срок | Где делается | Статус |
| --- | --- | --- | --- | --- |
| 1 | Уведомление в РКН об обработке персональных данных (PD-02) | 24.10.2026, просрочено на 20 дней | https://pd.rkn.gov.ru/ ; значения полей — `docs/legal/personal-data.md` | подачи нет в репозитории (догадка: не подано) |
| 2 | Анкета о контенте и раскрытие ИИ в Steamworks (S6) | 20.11.2026 (осталось 7 дней) | https://partner.steamgames.com/ → страница игры | черновики готовы (`docs/marketing/steam-content-survey.md`), ждут ввода Kanta; раздел про ИИ — после проверки условий Meshy и Hunyuan (V-08), сверку готовит Claude |
| 3 | Проверка Valve по S1–S3 | около 16.11.2026 (осталось 3 дня) | Steamworks, статус проверки | ждёт Valve, действий Kanta нет |
| 4 | Демо и страница игры на проверку Valve (DM-10) | 18.01.2027 по Steamworks (осталось 66 дней); в `docs/process/early-access.md` стоит 25.01 — сверить | Steamworks → страница игры → демо | после пункта 3 |
| 5 | Регистрация игры на Steam Next Fest (DM-10) | 10.01.2027 (осталось 58 дней); старт фестиваля 22.02.2027 (осталось 101 день) | Steamworks → страница игры → фестивали | после пункта 4 |
| 6 | «ок» на 7 капсул и 8 скриншотов Steam (R-29) | нужно для страницы; срок не назван (догадка: до пункта 4) | https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WL7tQUNACaf3j1DA8bm5TsK | ждёт «ок» |
| 7 | Вставить строку в `settings.json` для `tools/pc/*.ps1` (R-17) и новый промпт планёрки в рутину (R-21) | к следующей сборке | на ПК: `settings.json`; рутина — настройки планёрки | ждёт Kanta (координатор не может менять рутину) |

## Ждёт решения Kanta (без срока)

- Еженедельное ревью 13.11: ответить цифрами на 7 предложений (первыми 1–3: капсулы Steam и V-08 до 20.11, исправление колонн отдельно от баланса, посты без «ок») — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WEjqUhqJjoJUfBirGkWeWPf
- Пакет для бомб «Кита» (GD-18): выбрать 1, 2, 3 или «пока ничего»; Claude рекомендует 1 — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WLPHVyUCkgnVnEz7ziRJP9i
- Альбом сборок в бою (PG-16): посмотреть кадры и написать правки — https://claude.ai/artifact/AdfLagBdVKYw4ftXJJYYoe (тред — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WPkxNeDFgYAvWGWw6tv2EKm)
- Маркетинг: «ок» или правки на Дневник №4, №5, «Оружие в ангаре» и ещё два (в Word, в личке бота), пятничный рилс «Оса» — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WXg1Zyyd9Z1RQ643rufRAE6 (последний пост в канале — 10.11)
- Дорожная карта релиза в Steam: выбрать вариант раннего доступа (рекомендован B) — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WBSPszaJfkMh8vCSYpqH3Pa
- Заставки: «да» на перерисовку «Купола» и «Грома» (2 генерации Figma, тратят кредиты) — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WJQ7bnVMg1iWG5bFZBPD6pm
- Облачная видеокарта для рендера: после утверждения аниматика второй части напиши «считай» — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WKnuKi5ji4Ku4p3jNX3H7XG
- PR #600 (два издания): решение о слиянии (по состоянию на 10.11 открыт; на 12.11 не перепроверен) — https://github.com/kanta201196-hub/FlakHeaven/pull/600
- Сборка 3.5-s18: проверить в игре и отметить, что не так. Следующая сборка — только по команде Kanta.
- Тред бэкапа ждёт «удаляй» — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WNwxKTmyMY7of5Me5TYX4TB
- Ангар: «ок» на R-22 — https://claude.ai/artifact/MuwtyKLcKBfY8KJyWYguDC
- Камуфляж «Кит 2»: «ок» или что поправить — https://claude.ai/artifact/9gBFoPRHQRAcv1cmzTtpnM
- APK на Android (эксперимент) ждёт теста на телефоне — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WEVBC5J2UM79jZ1ct9zRUq3
- Бот тестеров «Старт» (PR в ревью) — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W8npvQTh1WDX9gLNnGD8FNE
- «Грач»: «да» или правки по шву, хвосту и полосе — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W51paqT882Z4wfzxcCJPcha
- Тред «Составить список для выхода в Steam» ждёт App ID от Valve (не Kanta) — https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W6HMX1ospp3M7eJsWDKo7Bq

## Сделано за сутки (для сверки)

- 12–13.11: кода в `main` не слито; коммиты — документы: #624 (обзор task-observer), строка бэклога по GD-18 (PR #623 ждёт «да»), план маркетинга W46 и статус 13.11.

- PR #619 (PG-17, лёгкий первый вылет), #620 (PG-13, «момент силы»), #621 (PG-16, альбом в бою) и #622 (PG-12 и PG-14, первая связка) слиты в `main` 11.11.
- Треды закрыты 11.11: «Упростить первый вылет новичка», «Сделать первую связку достижимой», «Показать «момент силы» в бою».
- Журнал: установлен task-observer как пробный навык (PR #618).
