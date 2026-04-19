# План реализации: Исправление нарушений Rubocop Layout/SpaceInsideArrayLiteralBrackets

**Issue:** #8
**Бриф:** [brief.md](brief.md)
**Спецификация:** [spec.md](spec.md)

## Обзор

Задача стилистическая. Трогаем две строки в двух файлах, приводя литералы массива к `EnforcedStyle: space` из `rubocop-rails-omakase`. Никаких backend/frontend изменений, миграций и новых гемов.

## Изменения Backend

Только правка двух Ruby-литералов:

- `lib/tasks/users.rake:3` — `[:email, :password]` → `[ :email, :password ]`
- `spec/mailers/passwords_mailer_spec.rb:10` — `["test@example.com"]` → `[ "test@example.com" ]`

## Изменения Frontend

Не применимо.

## Миграции

Не применимо.

## Зависимости / гемы

Новые гемы не добавляются. Версии `rubocop-rails-omakase` и прочих в `Gemfile` / `Gemfile.lock` не меняются.

## Способ правки

Ручная правка (по одному пробелу после `[` и перед `]` в каждом литерале).

**Обоснование выбора:** изменение затрагивает всего 2 строки, ручной способ детерминистичен, не требует предварительного `bundle install` и исключает риск, что автокорректор затронет что-то сверх целевых строк. Вариант `bin/rubocop -a --only Layout/SpaceInsideArrayLiteralBrackets` из спецификации остаётся допустимой альтернативой при необходимости.

---

## Шаги

### Шаг 1. Установить зависимости

**Вход:** чистая рабочая директория worktree, `bundle` установлен системно.
**Выход:** установленные гемы, рабочий `bin/rubocop`.
**Побочные эффекты:** изменений в репозитории нет (`Gemfile.lock` уже актуален).
**Затрагиваемые файлы:** нет.
**Команда:** `bundle install`
**Способ проверки:** `bin/rubocop --version` отрабатывает без `Bundler::GemNotFound`.

---

### Шаг 2. Зафиксировать baseline количества offenses

**Вход:** установленные гемы.
**Выход:** известное число offenses по всему проекту до правки — `BASELINE_TOTAL`, и число offenses `Layout/SpaceInsideArrayLiteralBrackets` — `BASELINE_SPACE = 4` (ожидаемо).
**Побочные эффекты:** нет.
**Затрагиваемые файлы:** нет.
**Команды:**
- `bin/rubocop --format offenses` — сохранить суммарное число offenses (вывод целиком).
- `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets` — ожидаем 4 offenses в двух файлах из брифа.
**Способ проверки:**
- `BASELINE_SPACE == 4` и локации: `lib/tasks/users.rake:3` + `spec/mailers/passwords_mailer_spec.rb:10`.
- Если число offenses или локации отличаются — возврат на этап 1 (бриф) с обновлением.

---

### Шаг 3. Правка `lib/tasks/users.rake:3`

**Вход:** строка `[:email, :password]` на строке 3.
**Выход:** строка `[ :email, :password ]` на той же позиции.
**Побочные эффекты:** нет (семантика литерала не меняется).
**Затрагиваемые файлы:** `lib/tasks/users.rake`.
**Действие:** добавить пробел после `[` и перед `]` в литерале на строке 3.
**Способ проверки:**
- `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets lib/tasks/users.rake` → 0 offenses.
- `git diff lib/tasks/users.rake` показывает ровно одну изменённую строку.

---

### Шаг 4. Правка `spec/mailers/passwords_mailer_spec.rb:10`

**Вход:** строка с `["test@example.com"]` на строке 10.
**Выход:** строка с `[ "test@example.com" ]` на той же позиции.
**Побочные эффекты:** нет (семантика литерала не меняется).
**Затрагиваемые файлы:** `spec/mailers/passwords_mailer_spec.rb`.
**Действие:** добавить пробел после `[` и перед `]` в литерале на строке 10.
**Способ проверки:**
- `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets spec/mailers/passwords_mailer_spec.rb` → 0 offenses.
- `git diff spec/mailers/passwords_mailer_spec.rb` показывает ровно одну изменённую строку.

---

### Шаг 5. Локальный прогон rubocop — целевой cop по двум файлам

**Вход:** правки шагов 3 и 4 применены.
**Выход:** подтверждение, что все 4 offenses устранены.
**Побочные эффекты:** нет.
**Затрагиваемые файлы:** нет.
**Команда:** `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets lib/tasks/users.rake spec/mailers/passwords_mailer_spec.rb`
**Способ проверки:** exit code 0, вывод `no offenses detected`.

---

### Шаг 6. Локальный прогон rubocop — весь проект

**Вход:** правки применены.
**Выход:** суммарное число offenses по проекту `TOTAL_AFTER == BASELINE_TOTAL − 4`.
**Побочные эффекты:** нет.
**Затрагиваемые файлы:** нет.
**Команды:**
- `bin/rubocop --format offenses` — сравнить с baseline из шага 2.
- `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets` — ожидаем 0 offenses по всему проекту.
**Способ проверки:**
- Число offenses вне `Layout/SpaceInsideArrayLiteralBrackets` не выросло относительно baseline из шага 2.
- `Layout/SpaceInsideArrayLiteralBrackets` показывает 0.
- Если число offenses иных cop'ов выросло — останавливаемся, возврат на этап плана (границы требуют не трогать другие файлы).

---

### Шаг 7. Полный прогон rspec

**Вход:** правки применены.
**Выход:** отсутствие регрессий.
**Побочные эффекты:** нет.
**Затрагиваемые файлы:** нет.
**Команда:** `bundle exec rspec`
**Способ проверки:** 0 failures, 0 errors; число тестов не уменьшилось.

---

### Шаг 8. Коммит и push

**Вход:** все локальные проверки пройдены.
**Выход:** коммит на ветке `features/008-fix-rubocop-array-brackets`, запушенный в origin.
**Побочные эффекты:** запуск CI на ветке.
**Затрагиваемые файлы:** `lib/tasks/users.rake`, `spec/mailers/passwords_mailer_spec.rb` (+ SDD-артефакты из `docs/features/008-fix-rubocop-array-brackets/`).
**Команды:**
- `git add lib/tasks/users.rake spec/mailers/passwords_mailer_spec.rb docs/features/008-fix-rubocop-array-brackets/`
- `git commit -m "fix: соблюсти Layout/SpaceInsideArrayLiteralBrackets в users.rake и passwords_mailer_spec"` (черновик; допустима адаптация под стиль репозитория)
- `git push -u origin features/008-fix-rubocop-array-brackets`
**Способ проверки:** `git status` чистый, ветка запушена.

---

### Шаг 9. Проверка CI

**Вход:** запушенный коммит.
**Выход:** зелёный lint job и зелёный полный pipeline.
**Побочные эффекты:** нет.
**Затрагиваемые файлы:** нет.
**Команды:**
- `gh run list --branch features/008-fix-rubocop-array-brackets --limit 1`
- `gh run watch $(gh run list --branch features/008-fix-rubocop-array-brackets --limit 1 --json databaseId -q '.[0].databaseId')` (при необходимости)
**Способ проверки:** все jobs (в т.ч. lint) завершаются с conclusion `success`.

---

### Шаг 10. Создание PR

**Вход:** зелёный CI на ветке фичи.
**Выход:** открытый PR `features/008-fix-rubocop-array-brackets` → `main` со ссылкой на issue #8.
**Побочные эффекты:** внешнее действие, видимое другим участникам; запуск CI на PR.
**Затрагиваемые файлы:** нет.
**Команда:** `gh pr create --base main --head features/008-fix-rubocop-array-brackets --title "..." --body "..."` (title/body формируются на этапе приёмки; в теле — ссылка на issue #8).
**Способ проверки:** PR создан, CI на PR зелёный, issue #8 привязан.

---

## Тестовая стратегия

### Что тестируется

| Уровень | Покрытие | Обоснование |
|---------|----------|-------------|
| **Lint (static)** | `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets` по двум файлам и по всему проекту | Основная проверка — что правка устраняет нарушения и не вносит новых. |
| **Lint (static, regression)** | `bin/rubocop --format offenses` до/после | Критерий приёмки: offenses по остальным cop'ам не выросли. |
| **Regression (rspec suite)** | `bundle exec rspec` целиком | Отсутствие регрессий во всём проекте (включая `spec/mailers/passwords_mailer_spec.rb`). |
| **CI (pipeline)** | GitHub Actions на ветке и на PR | Конечный критерий — lint job проходит. |

### Что сознательно не покрыто тестами

- **Новые unit-тесты для `users:create` и `PasswordsMailer`.** Правка чисто стилистическая: литералы `[:a, :b]` и `[ :a, :b ]` тождественны на уровне Ruby-парсера. Добавлять тесты на «не изменилась семантика» — работа без ценности, покрытие уже обеспечивается существующим `passwords_mailer_spec.rb` и прогоном всего rspec.
- **Проверка на других стилистических cop'ах.** Вне границ фичи (см. бриф).
- **Локальная проверка CI-воркфлоу (act / nektos).** CI исполняется на GitHub после push; дублирующая локальная эмуляция даёт лишнюю сложность без выигрыша.

## Риски и откат

- Если `bin/rubocop --format offenses` после правки покажет рост суммарного числа offenses — откатить изменения (`git restore <файлы>`), вернуться к шагу 3 и выяснить источник расхождения.
- Если `bin/rubocop --only Layout/SpaceInsideArrayLiteralBrackets` после правки найдёт дополнительные нарушения за пределами двух целевых файлов — возврат на этап 1 (бриф) для расширения границ.
- Если `rspec` упал после правки — противоречит инвариантам спецификации (семантика литерала не меняется); нужно остановиться и разбираться, а не править тесты.
