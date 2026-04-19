# [APPROVED] Спецификация: Исправление нарушений Rubocop Layout/SpaceInsideArrayLiteralBrackets

**Issue:** #8
**Бриф:** [brief.md](brief.md)

> **[Approved by @dniman 2026-04-19]**
> Спецификация прошла ревью (уровень: quick).
> Итераций: 1. Критичных замечаний: 0. Исправлено: 0.

## Контекст

`.rubocop.yml` наследует правила из `rubocop-rails-omakase`:

```yaml
inherit_gem: { rubocop-rails-omakase: rubocop.yml }
```

В omakase для `Layout/SpaceInsideArrayLiteralBrackets` включён `EnforcedStyle: space` — внутри квадратных скобок литерала массива должны быть пробелы.

В двух файлах проекта стиль нарушен:

- `lib/tasks/users.rake:3` — `[:email, :password]`
- `spec/mailers/passwords_mailer_spec.rb:10` — `["test@example.com"]`

Rubocop фиксирует 2 offenses на литерал (открывающая и закрывающая скобка) → 4 offenses суммарно. CI lint job падает из-за них.

## Архитектурные решения

Задача чисто стилистическая, архитектура не затрагивается.

### Целевой формат

- `lib/tasks/users.rake:3` → `[ :email, :password ]`
- `spec/mailers/passwords_mailer_spec.rb:10` → `[ "test@example.com" ]`

### Способ правки

Допустимы оба варианта:

- ручная правка (добавить по одному пробелу после `[` и перед `]`);
- `bin/rubocop -a --only Layout/SpaceInsideArrayLiteralBrackets lib/tasks/users.rake spec/mailers/passwords_mailer_spec.rb`.

Ограничение `--only` используется, чтобы автокорректор не зацепил другие cop'ы.

### Границы изменений

Трогаются ровно две строки в двух файлах. Никакие другие файлы, включая `.rubocop.yml`, `Gemfile`, `Gemfile.lock`, не модифицируются. Логика rake-задачи `users:create` и тестов `PasswordsMailer` не меняется — литерал `[:a, :b]` и `[ :a, :b ]` семантически идентичны.

## Модели данных

Не применимо.

## Поведение UI

Не применимо.

## Edge cases

1. **Локальный запуск rubocop невозможен без `bundle install`.**
   На текущей машине `bin/rubocop` падает с `Bundler::GemNotFound: pagy-43.5.1`. Перед правкой/проверкой требуется выполнить `bundle install`.

2. **Автокорректор меняет больше, чем ожидалось.**
   Блокируется флагом `--only Layout/SpaceInsideArrayLiteralBrackets`. Если автокорректор всё же затронет что-то сверх двух целевых строк — такие изменения откатываются, правка остаётся в границах брифа.

3. **В проекте появились новые нарушения того же cop'а, помимо известных двух.**
   Бриф допускает, что их нет (пункт «Допущения»). Если прогон rubocop после правки покажет ненулевой остаток `Layout/SpaceInsideArrayLiteralBrackets` — возврат на этап 1 (бриф) с обновлением списка локаций.

4. **Семантическое изменение литерала.**
   Исключено: `[:a, :b]` и `[ :a, :b ]` — один и тот же Array-литерал для Ruby-парсера. Существующие тесты `PasswordsMailer` и rake-задача `users:create` после правки должны работать без изменений.

5. **Расхождение версий rubocop-rails-omakase между локально и CI.**
   Версия зафиксирована в `Gemfile.lock`, отдельно не меняется. Риск отсутствует, пока не трогаем Gemfile.

## Соответствие критериям приёмки

| Критерий из брифа | Как адресован |
|---|---|
| `bin/rubocop` по двум файлам — 0 нарушений `Layout/SpaceInsideArrayLiteralBrackets` | Целевой формат соответствует `EnforcedStyle: space` omakase |
| `bin/rubocop` по всему проекту — offenses не выросли | Изменения локализованы двумя строками; автокорректор ограничен одним cop'ом |
| `rspec spec/mailers/passwords_mailer_spec.rb` проходит | Литерал семантически не меняется |
| Полный `rspec` — без регрессий | То же основание |
| CI lint job на ветке — проходит | 4 известных offenses устраняются, новые не вносятся |

## Открытые вопросы

Нет.
