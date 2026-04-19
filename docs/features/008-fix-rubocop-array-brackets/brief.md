# Бриф: Исправление нарушений Rubocop Layout/SpaceInsideArrayLiteralBrackets

**Issue:** #8

## Что делаем

Исправляем 4 нарушения `Layout/SpaceInsideArrayLiteralBrackets` в двух файлах:

- `lib/tasks/users.rake:3` — литерал `[:email, :password]`
- `spec/mailers/passwords_mailer_spec.rb:10` — литерал `["test@example.com"]`

Rubocop фиксирует по одному offense на каждую скобку литерала: 2 литерала × 2 скобки (открывающая + закрывающая) = 4 offenses.

Проект использует `rubocop-rails-omakase`, правило требует пробелы внутри квадратных скобок (`[ :email, :password ]`). Приводим литералы к этому стилю.

## Зачем

Lint job в CI падает из-за этих предсуществующих нарушений. Это блокирует прохождение CI для любых PR, пока нарушения не устранены.

## Границы

**Входит:**
- Правка литерала массива в `lib/tasks/users.rake:3`
- Правка литерала массива в `spec/mailers/passwords_mailer_spec.rb:10`
- Приведение файлов к соответствию `Layout/SpaceInsideArrayLiteralBrackets` из `rubocop-rails-omakase`

**Вне границ:**
- Исправление других cop'ов Rubocop, если они всплывут
- Правка файлов за пределами двух указанных
- Изменение конфигурации Rubocop (`.rubocop.yml`)
- Изменение логики rake-задачи `users:create` и тестов `PasswordsMailer`
- Любой рефакторинг, не связанный с расстановкой пробелов

## Критерии приёмки

- При запуске `bin/rubocop lib/tasks/users.rake spec/mailers/passwords_mailer_spec.rb` — 0 нарушений `Layout/SpaceInsideArrayLiteralBrackets`
- При запуске `bin/rubocop` по всему проекту — количество offenses не увеличилось относительно `main` (для остальных cop'ов)
- При запуске `bundle exec rspec spec/mailers/passwords_mailer_spec.rb` — все существующие тесты проходят
- При запуске полного набора `bundle exec rspec` — регрессий нет
- При выполнении lint job в CI на ветке фичи — job проходит успешно

## Допущения

- Допустимый способ правки — любой (ручной либо `bin/rubocop -a`), результат один и тот же — стиль `EnforcedStyle: space` из omakase
- Других нарушений `Layout/SpaceInsideArrayLiteralBrackets` в проекте нет (issue явно называет только эти 4)

## Открытые вопросы

Нет.
