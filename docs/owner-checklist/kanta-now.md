# Только Kanta: что не может сделать Claude

Обновлено: 09.11.2026

Первый пункт каждой планёрки (решение Kanta 22.10.2026, ревью 5.7). Не больше 7 пунктов. Планёрка показывает, сколько дней до срока. Сделанное — вычёркивать и переносить в `checklist.md` с датой.

Статусы 09.11 взяты из того, что Kanta написал за последние сутки (треды и чат). Всё, что не подтверждено его сообщением, помечено как догадка.

| № | Что | Срок | Где делается | Статус |
| --- | --- | --- | --- | --- |
| 1 | Уведомление в РКН об обработке персональных данных (PD-02) | 24.10.2026, просрочено на 16 дней | https://pd.rkn.gov.ru/ ; значения полей — `docs/legal/personal-data.md` | отметки «подал» нет (догадка: не подано, в переписке за сутки не упоминалось) |
| 2 | Анкета о контенте и раскрытие ИИ в Steamworks (S6) | 20.11.2026 (осталось 11 дней) | https://partner.steamgames.com/ → страница игры | черновики готовы (`docs/marketing/steam-content-survey.md`), ждут ввода Kanta; раздел про ИИ — после проверки условий Meshy и Hunyuan (V-08) |
| 3 | Проверка Valve по S1–S3 | около 16.11 (осталось 7 дней) | Steamworks, статус проверки | ждёт Valve, действий Kanta нет |
| 4 | Демо и страница игры на проверку Valve (DM-10) | 18.01.2027 по Steamworks (осталось 70 дней); в `docs/process/early-access.md` стоит 25.01 — сверить | Steamworks → страница игры → демо | после пункта 3 |
| 5 | Регистрация игры на Steam Next Fest (DM-10) | 10.01.2027 (осталось 62 дня); старт фестиваля 22.02.2027 (осталось 105 дней) | Steamworks → страница игры → фестивали | после пункта 4 |
| 6 | Вставить строку в `settings.json` для `tools/pc/*.ps1` (R-17) и новый промпт планёрки в рутину (R-21) | к следующей сборке | на ПК: `settings.json`; рутина — настройки планёрки | ждёт Kanta (координатор не может менять рутину) |

Дальше по очереди: кадры и трейлер для страницы Steam (конец ноября).

## Сделано за сутки (для сверки)

- Береговая батарея (B2-A01): Kanta ответил 09.11 на все 12 пунктов, PR #615 слит (`e0070bb`). Ждёт проверки в игре в следующей сборке.

## Ждёт ответа Kanta (не срочные сроки)

- Слить PR #600 (два издания: ливреи и наклейки, ED-03/04/08), открыт, проверки зелёные: решение Kanta, сливать ли самому — https://github.com/kanta201196-hub/FlakHeaven/pull/600
- Заставки: «да» на перерисовку «Купола» и «Грома» — тред https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WJQ7bnVMg1iWG5bFZBPD6pm (со слов координатора, в репозитории не проверено)
- Серия 0 (маркетинг): аниматик части 2 придёт в тред на просмотр; полный счёт видео — только после «да» — тред https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WXg1Zyyd9Z1RQ643rufRAE6
- «Грач»: голый металл хвоста, светлая полоса под пластиной «Грача 1», шов на борту — «да» или правки: тот же тред 3D-моделей
- Отзыв по 6 шортсам и «ок» на описание YouTube-канала: тред Маркетинг и реклама https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WXg1Zyyd9Z1RQ643rufRAE6
- Бот тестеров, «Старт» (PR в ревью с 06.11): https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W8npvQTh1WDX9gLNnGD8FNE
- APK на Android (эксперимент) ждёт теста на телефоне: тред https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WEVBC5J2UM79jZ1ct9zRUq3
- Тред бэкапа ждёт «удаляй»: https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2WNwxKTmyMY7of5Me5TYX4TB
- Ангар: «ок» на R-22 (детали ангара включены, свет выключен) — страница https://claude.ai/artifact/MuwtyKLcKBfY8KJyWYguDC
- Камуфляж: кадры «Кит 2» после правки тёмных пятен на гондоле (#544) — «ок» или что поправить: https://claude.ai/artifact/9gBFoPRHQRAcv1cmzTtpnM
- Тред «Составить список для выхода в Steam» ждёт App ID от Valve (не Kanta): https://claude.ai/code/project/chan_01SdohJnNRxu3TbJs1P3Ny2W?thread=cmsg_01SdohJnNRxu3TbJs1P3Ny2W6HMX1ospp3M7eJsWDKo7Bq
