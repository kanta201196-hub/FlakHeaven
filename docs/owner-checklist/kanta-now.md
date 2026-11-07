# Только Kanta: что не может сделать Claude

Первый пункт каждой планёрки (решение Kanta 22.10.2026, ревью 5.7). Не больше 7 пунктов. Планёрка показывает, сколько дней до срока. Сделанное — вычёркивать и переносить в `checklist.md` с датой. Обновлено: 07.11.2026 (планёрка, R-21). Сделано и снято с 06.11: PR #539 (пресет Windows Release, `tools/steam/upload.sh`) слит 03.11; сборка 3.5-s17 собрана 06.11 по команде Kanta 11:44 UTC. Статусы по сутки не подтверждены Kanta: пункт 2 (s17) и пункт 1 (РКН) проверить в треде.

| № | Что | Срок | Где делается | Статус |
| --- | --- | --- | --- | --- |
| 1 | Уведомление в РКН об обработке персональных данных (PD-02) | 24.10.2026, просрочено на 14 дней | https://pd.rkn.gov.ru/ ; значения полей — `docs/legal/personal-data.md` | отметки «подал» нет (07.11) |
| 2 | Сборка 3.5-s17: нажать «Разрешить» на карточке удалённого управления (Remote Control) в треде сборки — ПК выложит её на itch.io и Диск | собрана 06.11 по команде Kanta 11:44 UTC; следующая не раньше 07.11 и только по его команде | Тред сборки s17 (cmsg_01SdohJnNRxu3TbJs1P3Ny2W3S6TXiDueVdntzTNCVHjuv); страница «что проверить» придёт с ней | ждёт проверку и выкладку (не подтверждено) |
| 3 | Анкета о контенте и раскрытие ИИ в Steamworks (S6) | 20.11.2026 (осталось 13 дней) | https://partner.steamgames.com/ → страница игры | черновики готовы (`docs/marketing/steam-content-survey.md`), ждут ввода Kanta; раздел про ИИ — после проверки условий Meshy и Hunyuan (V-08) |
| 4 | Проверка Valve: ждём результат по S1–S3 | около 16.11 (осталось 9 дней) | Steamworks, статус проверки | ждёт Valve, действий Kanta нет |
| 5 | Демо и страница игры на проверку Valve (DM-10) | 18.01.2027 по Steamworks (осталось 72 дня); в `docs/process/early-access.md` стоит 25.01 (осталось 79 дней) — сверить | Steamworks → страница игры → демо | после пункта 4 |
| 6 | Регистрация игры на Steam Next Fest (DM-10) | 10.01.2027 (осталось 64 дня); старт фестиваля 22.02.2027 (осталось 107 дней) | Steamworks → страница игры → фестивали | после пункта 4 |
| 7 | Вставить строку в `settings.json` для `tools/pc/*.ps1` (R-17) и новый промпт планёрки в рутину (R-21) | к следующей сборке | на ПК: `settings.json`; рутина — настройки планёрки | ждёт Kanta (координатор не может менять рутину) |

Дальше по очереди: кадры и трейлер для страницы Steam (конец ноября).

## Ждёт ответа Kanta (не срочные сроки)

- Meshy, модели уровней 4–5: вопрос Kanta про режим перегенерации (он дешевле) отвечён карточкой в треде; выбрать вариант 1, 2 или 3 (рекомендация 1: обе модели без текстуры, 50 кредитов, останется 224): https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W51paqT882Z4wfzxcCJPcha (страница с шестью моделями: https://claude.ai/artifact/Tqqkf9Be7sZyK9hfB6WkUv)
- «Грач»: голый металл хвоста, светлая полоса под пластиной «Грача 1», шов на борту — «да» или правки: тот же тред 3D-моделей
- Отзыв по 6 шортсам и «ок» на описание YouTube-канала: тред Маркетинг и реклама https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WXg1Zyyd9Z1RQ643rufRAE6
- Бот тестеров, «Старт» (PR в ревью): https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W8npvQTh1WDX9gLNnGD8FNE
- APK на Android (эксперимент) ждёт теста на телефоне: тред https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WEVBC5J2UM79jZ1ct9zRUq3
- Тред бэкапа ждёт «удаляй»: https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WNwxKTmyMY7of5Me5TYX4TB
- Тред «Составить список для выхода в Steam» ждёт App ID от Valve (не Kanta): https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W6HMX1ospp3M7eJsWDKo7Bq
- Ангар: «ок» на R-22 (детали ангара включены, свет выключен) — страница https://claude.ai/artifact/MuwtyKLcKBfY8KJyWYguDC
- Камуфляж: кадры «Кит 2» после правки тёмных пятен на гондоле (#544) — «ок» или что поправить: https://claude.ai/artifact/9gBFoPRHQRAcv1cmzTtpnM
