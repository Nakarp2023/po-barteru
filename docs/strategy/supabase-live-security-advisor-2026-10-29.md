# Снимок живых Supabase Security Advisor — 29.10.2026

**Проект:** `po-barteru` (`qxsnjksepzmpsifpxyea`)  
**Метод:** чтение текущих Supabase Advisors и каталога функций. Никакие изменения в БД не выполнялись.  
**Важно:** результаты Advisor — сигналы для проверки, не автоматическое доказательство уязвимости.

## Текущее состояние проекта

- Supabase project status: `ACTIVE_HEALTHY`.
- Регион проекта: `eu-west-1`.
- PostgreSQL: 17.11.
- Security Advisor наблюдение: 2026-10-29 18:35 UTC.

## Security Advisor — результаты

### WARN: 6 SECURITY DEFINER RPC доступны роли authenticated

Advisor помечает следующие функции, вызываемые через Data API:
- `public.cancel_exchange_deal(uuid)`
- `public.confirm_exchange_completed(uuid)`
- `public.confirm_exchange_terms(uuid)`
- `public.mark_conversation_messages_read(uuid)`
- `public.respond_to_exchange_proposal(uuid, text)`
- `public.update_exchange_terms(uuid, text, numeric, text)`

Статический просмотр определений показал проверки `auth.uid()` и проверку участия/состояния в ряде функций. Это не повод автоматически отзывать EXECUTE: приложение может зависеть от этих RPC, а некоторые функции являются частью корректного серверного workflow. Следующие действия:
1. Для каждой функции проверить все ветви кода, ownership/participant checks, блокировки, проверки статусов, права на изменяемые строки и привилегии владельца.
2. Провести отрицательные тесты на отдельной тестовой базе/ветке: anon, пользователь вне сделки, другой участник, повторный вызов, гонка состояний, некорректные/NULL параметры.
3. Проверить grants и `search_path`; функции в этом списке имеют `SET search_path TO ''` в просмотренных определениях, что является полезной мерой, но не заменяет проверки логики.
4. Не менять grants и не переписывать функции в production до завершения тестов и отдельного согласования.

Документация Supabase предупреждает, что SECURITY DEFINER выполняется с привилегиями владельца функции, поэтому важны строгие проверки в теле, безопасный search_path и минимальные grants.

### WARN: защита от скомпрометированных паролей отключена

Advisor рекомендует включить проверку паролей по Have I Been Pwned. Предлагаемое исправление: проверить настройки Auth, оценить пользовательские сценарии входа/смены пароля, затем включить настройку через согласованное окно и протестировать. В этом аудите переключатель не менялся.

### INFO: RLS включён, политики отсутствуют у payment_webhook_events

`public.payment_webhook_events` отмечена Advisor как таблица с включённым RLS без политик. Предыдущий аудит указывает, что у клиентских ролей нет grants и таблица используется как server-only ledger webhook-событий. Это может быть правильной конфигурацией. Не добавлять публичные политики. Проверить grants, доступность через API и запись только доверенным webhook/backend-кодом.

## Performance Advisor

Advisor показывает 19 неиспользуемых индексов. Это предупреждения, а не рекомендация немедленно удалять индексы. Для молодого проекта статистика использования может быть непоказательной. Нужны проверка запросов, EXPLAIN/нагрузочные измерения и оценка индексов, поддерживающих уникальность, внешние ключи, ограничения, безопасность и критичные сценарии.

## Изменения, которые пока НЕ выполнялись

- Не менялись grants/RLS/policies.
- Не выполнялись миграции и DDL.
- Не менялись статусы сделок, платежей, заказов или подписок.
- Не менялись настройки Auth.
- Не выполнялась ротация VAPID-ключа или иных секретов.
- Не выполнялись destructive/performance-оптимизации.

## Ближайшие шаги

1. Прочитать определения всех шести RPC полностью и составить матрицу проверок.
2. Проверить grants на функции и доступность exposed schemas.
3. Организовать негативные тесты вне production.
4. Проверить Auth password security и согласовать безопасное включение.
5. Перепроверить Data API exposure и явные grants в связи с изменением Supabase, вступающим в силу 30.10.2026: новые таблицы не должны автоматически считаться доступными через Data API. Для каждой новой таблицы нужны явные решения по экспонированию, GRANT и RLS.
6. После исправлений повторно запустить Security и Performance Advisors и приложить сравнение.

## Ссылки

- [Supabase Security Advisor](https://supabase.com/dashboard/project/qxsnjksepzmpsifpxyea/advisors/security)
- [Supabase Database Linter: SECURITY DEFINER grants](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Supabase Password Security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- [Supabase: таблицы не экспонируются автоматически](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
