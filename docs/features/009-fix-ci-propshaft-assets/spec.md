# Спецификация: Propshaft::MissingAssetError в CI-тестах [APPROVED]

**Issue:** #9
**Бриф:** [brief.md](./brief.md)

> **[Approved by @dniman 2026-04-19]**
> Спецификация прошла архитектурное и бизнес-ревью.
> Итерация: 1. Обработано проблем: 12 (4 приняты в спеку, 2 переклассифицированы в medium, 1 вынесена в follow-up issue, 5 отклонены как избыточные для инфра-фикса).

## 1. Диагноз

### 1.1 Как ассеты собираются в проекте

Стек сборки фронтенд-ассетов:

- **Propshaft 1.3.1** — ассет-pipeline Rails, ищет ассеты в `app/assets/*` и `app/assets/builds/`
- **jsbundling-rails 1.3.1** — интеграция внешних JS-бандлеров (Bun), добавляет `app/assets/builds` в Propshaft load path и подключает `bun run build` к `assets:precompile` через rake-хук `javascript:build`
- **cssbundling-rails 1.4.3** — аналогично для CSS (Tailwind), хук `css:build`
- **Bun 1.3.5** (версия зафиксирована в `Dockerfile`, `ARG BUN_VERSION=1.3.5`) — сборщик

Entrypoint сборки:

- JS: `app/javascript/application.js` → `app/assets/builds/application.js` (через `bun bun.config.js`, см. `package.json:build`)
- CSS: `app/assets/stylesheets/application.tailwind.css` → `app/assets/builds/application.css` (через `bunx @tailwindcss/cli --minify`, см. `package.json:build:css`)

Директория `app/assets/builds/` существует в репозитории, но в неё коммитится только `.keep`; собранные файлы артефакты и не хранятся в git.

### 1.2 Как лейаут потребляет ассеты

`app/views/layouts/application_layout.rb:28-29`:

```ruby
stylesheet_link_tag :app, "data-turbo-track": "reload"
javascript_include_tag "application", "data-turbo-track": "reload", type: "module"
```

`javascript_include_tag "application"` заставляет Propshaft искать `application.js` в load path. Если файла нет ни в `app/assets/builds/`, ни в `public/assets/.manifest.json`, Propshaft кидает `Propshaft::MissingAssetError`.

### 1.3 Почему падает CI, но не локально

Локально `app/assets/builds/application.js` присутствует как артефакт предыдущих запусков `bin/dev` (в `Procfile.dev` crons `bun run build --watch` и `bun run build:css --watch`), поэтому Propshaft находит файл и `javascript_include_tag` успешно рендерит путь.

В CI (`.github/workflows/ci.yml`, job `test`) на эфемерном ubuntu-runnere между checkout и `bundle exec rspec` шаги по сборке ассетов отсутствуют:

1. `actions/checkout@v6` — чистый чекаут, `app/assets/builds/` пустая
2. `ruby/setup-ruby@v1` с `bundler-cache: true`
3. `bin/rails db:prepare`
4. `bundle exec rspec` — падает

Bun не установлен на runner-е по умолчанию, зависимости `node_modules` не ставятся, сборка JS/CSS не выполняется.

### 1.4 Подтверждённый failing CI run

Run `24566039560` (commit `095896a`, ветка `main`, 2026-04-17):

- `59 examples, 21 failures`, все с `Propshaft::MissingAssetError: application.js`
- Все падения — на шаге рендера лейаута `Views::Layouts::ApplicationLayout` в:
  - `spec/requests/passwords_spec.rb` (3 теста: `:7`, `:34`, `:63`)
  - `spec/requests/sessions_spec.rb` (4 теста: `:7`, `:25`, `:31`, `:37`)
  - `spec/views/layouts/application_layout_spec.rb` (10 тестов)
  - `spec/views/sessions/new_view_spec.rb` (4 теста)

CSS (`application.css`) в failing trace не фигурирует, но собирается из того же пайплайна и отсутствует в CI по той же причине — отсутствие `stylesheet_link_tag :app` в падающих тестах отражает то, что `javascript_include_tag` проверяется первым в `<head>` и поднимает исключение раньше. Без фикса JS падение CSS вскроется следом.

## 2. Архитектурное решение

### 2.1 Рассмотренные варианты

| # | Вариант | Оценка |
|---|---------|--------|
| а | `bin/rails assets:precompile` перед `rspec` | Выбран (см. 2.2). Canonical Rails way, воспроизводит прод-поведение |
| б | Заглушить `Propshaft::MissingAssetError` в test-окружении | Отклонено — маскирует реальные регрессии (опечатки в путях, сломанная сборка) и противоречит «запрет на изменение тестов» из брифа |
| в | Коммитить placeholder `app/assets/builds/application.js` как fixture | Отклонено — файл будет перезаписан любым `bin/dev`/`bun run build` локально, создаёт постоянный шум в git. Не валидирует реальную сборку |
| г | Отключить digest/asset-lookup в test | Отклонено — то же что (б), плюс Propshaft-специфичная семантика конфигурации не даёт чистого «отключить lookup» без монкипатча |

### 2.2 Выбранное решение

Добавить в job `test` в `.github/workflows/ci.yml` перед шагом `Run tests` сборку фронтенд-ассетов через canonical Rails way — `bin/rails assets:precompile`. Rake-таск precompile через jsbundling/cssbundling хуки автоматически запускает `bun run build` и `bun run build:css`, формируя файлы в `app/assets/builds/`, где их находит Propshaft.

Для работы precompile нужны:

1. Установленный Bun (версия читается из единого источника — файла `.bun-version` в корне репозитория; тот же файл используется и в `Dockerfile`)
2. Установленные фронтенд-зависимости (`bun install --frozen-lockfile`)

### 2.3 Почему precompile, а не прямой вызов `bun run build`

- `assets:precompile` — стандартный Rails-контракт, не зависит от имён скриптов в `package.json` и того, какой бандлер используется. Устойчив к будущей замене Bun на другой бандлер или добавлению новых entrypoint-ов
- Полнее воспроизводит прод-поведение (тот же шаг, что выполняется в `Dockerfile`) — совпадает с принципом «CI должен ловить регрессии, которые проявятся в проде»
- Одной строкой поднимает и JS, и CSS сборку через соответствующие хуки (`javascript:build`, `css:build`), без дублирования в workflow

Стоимость — несколько лишних секунд на digest-проход Propshaft и запись в `public/assets`, приемлемо.

## 3. Детальные изменения

### 3.1 `.github/workflows/ci.yml`

В job `test` (между шагом `Set up Ruby` и `Prepare database`) добавляются шаги:

```yaml
- name: Set up Bun
  uses: oven-sh/setup-bun@v2
  with:
    bun-version-file: .bun-version

- name: Install JS dependencies
  run: bun install --frozen-lockfile

- name: Precompile assets
  run: bin/rails assets:precompile
  env:
    RAILS_ENV: test
```

Точные правки:

- **Действие:** `oven-sh/setup-bun@v2` — официальный action для установки Bun на GitHub runner. Версия читается из `.bun-version` (`bun-version-file`, поддержка встроена в action начиная с v2) — единый источник истины, тот же файл использует `Dockerfile`
- **`--frozen-lockfile`** — обязательный режим для CI: сборка фейлится, если `bun.lock` и `package.json` рассинхронизированы (защита от недетерминированных версий зависимостей)
- **`RAILS_ENV: test`** на шаге precompile — ассеты собираются в том же окружении, в котором запускается rspec; уже объявлен на уровне job-а `env`, но повторён на уровне шага для явности (Rails читает `RAILS_ENV` при загрузке окружения)
- Порядок: setup bun → bun install → precompile — `bun install` нужен для `@tailwindcss/cli` и прочих фронтенд-зависимостей из `package.json`
- Точка вставки — перед `Prepare database`, т.к. precompile загружает Rails окружение, но не требует БД; ставим до `db:prepare`, чтобы при ошибке сборки CI падал раньше и давал более понятный фидбек

### 3.2 Другие файлы

Помимо `.github/workflows/ci.yml` правки затрагивают:

- **Новый файл `.bun-version`** в корне репозитория с содержимым `1.3.5` — единый источник истины для версии Bun
- **`Dockerfile`**: заменить `ARG BUN_VERSION=1.3.5` на чтение версии из `.bun-version` (например, `ARG BUN_VERSION` + `COPY .bun-version /tmp/.bun-version` + `RUN BUN_VERSION=$(cat /tmp/.bun-version) ...`, точная форма — в плане реализации)

Код приложения (`config/environments/test.rb`, `config/initializers/assets.rb`, `app/views/layouts/application_layout.rb`, спеки) не меняется — это сохраняет условие брифа «никаких изменений в самих тестах» и не влияет на поведение локальной разработки.

## 4. Поведенческие инварианты

### 4.1 CI (после фикса)

- При каждом push/PR, после checkout, CI устанавливает Bun 1.3.5, ставит фронтенд-зависимости (`bun install --frozen-lockfile`) и собирает ассеты (`bin/rails assets:precompile`) до запуска `rspec`
- После precompile в `app/assets/builds/` существуют `application.js` и `application.css`, в `public/assets/` существует `.manifest.json` с digest-путями
- Propshaft в тестовом окружении при `javascript_include_tag "application"` и `stylesheet_link_tag :app` находит ассеты и успешно рендерит теги
- Job `test` завершается с exit 0, все 59 тестов проходят (при отсутствии регрессий по другим причинам)

### 4.2 Локальная разработка (инвариант)

- Разработчик продолжает работать через `bin/dev` (watch-сборка), как сейчас
- `bundle exec rspec` локально использует артефакты от `bin/dev`/предыдущего `bun run build` — поведение не меняется
- Локально необязательно запускать `assets:precompile` перед тестами, т.к. watch-процессы обеспечивают наличие файлов в `app/assets/builds/`

### 4.3 Прод (инвариант)

- `Dockerfile` и `kamal` деплой не меняются, прод-путь через `bin/rails assets:precompile` в Docker-билде — тот же, что был

## 5. Edge cases

1. **`bun.lock` не синхронизирован с `package.json`** → `bun install --frozen-lockfile` фейлится, CI падает с явной ошибкой несоответствия версий. Это желаемое поведение; фиксится локальным `bun install` и коммитом обновлённого `bun.lock`
2. **Ошибка сборки JS (синтаксическая в `app/javascript/`)** → `bun run build` (через хук `javascript:build`) возвращает ненулевой код, `assets:precompile` падает, CI падает на шаге `Precompile assets`. Нужное поведение — CI должен ловить такие ошибки
3. **Ошибка сборки CSS (опечатка в Tailwind-директиве)** → аналогично через хук `css:build`
4. **Отсутствие `package.json` или `bun.lock`** → не применимо (файлы в репозитории, покрыто checkout-ом)
5. **Изменение entrypoint-а в `bun.config.js`** → spec не предписывает зависимость от конкретного entrypoint-а; Rails-контракт `assets:precompile` использует то, что прописано в `package.json:build`/`build:css`, поэтому переименование не ломает CI-шаг
6. **Ubuntu-раннер меняет major-версию** → action `oven-sh/setup-bun@v2` поддерживает текущие ubuntu-LTS-образы, версия Bun зафиксирована и не зависит от образа. Пин `@v2` сам по себе плавающий в рамках major-версии, но это стандартная практика GitHub Actions; чёткий pin коммита не требуется для внутреннего CI

## 6. Критерии приёмки (из брифа + mapping)

| # | Критерий из брифа | Как адресован |
|---|---|---|
| 1 | На чистом чекауте шаг `bundle exec rspec` в CI не падает с `Propshaft::MissingAssetError` | §3.1: ассеты собираются до `rspec`, файлы присутствуют в `app/assets/builds/` |
| 2 | Job `test` завершается с exit 0, регрессий по другим тестам нет | §4.1: все 21 падавший тест проходит; по остальным 38 — поведение не изменено (правки только в workflow). **Регрессия = тест, проходивший до PR, падает после мержа.** Время выполнения job и предупреждения CI-лога — вне acceptance criteria |
| 3 | Локально `bundle exec rspec` проходит без изменений кода тестов | §4.2: в коде приложения и тестов правок нет; локальный путь сборки через `bin/dev` сохранён |
| 4 | Dev-режим после фикса: рендеринг лейаутов и загрузка `application.js` работают | §4.2, §4.3: правки в workflow не влияют на `config/environments/development.rb` и на `Procfile.dev` |

## 7. Верификация (high-level)

Для ревью/плана (детализация — в фазе плана):

1. Локально запустить `rspec` после `bundle exec rails assets:precompile` — должен пройти (baseline того, что precompile достаточно)
2. Пушнуть ветку с правкой `ci.yml` — CI должен выдать зелёный `test` job
3. Сравнить список падавших тестов (§1.4) с итоговым отчётом CI — все 21 должны стать `pass`

## 8. Допущения (явные)

- `oven-sh/setup-bun@v2` доступен и стабилен на ubuntu-latest (на момент написания — `ubuntu-24.04`)
- Версия Bun читается из `.bun-version` в корне репозитория; `Dockerfile` и `setup-bun@v2` используют тот же файл, поэтому обновление версии в одном месте автоматически отражается в обоих окружениях
- Время работы шагов `setup-bun` + `bun install` + `assets:precompile` в CI — порядка 10–30 секунд; для текущего объёма тестов приемлемо. Оптимизация (кеширование `~/.bun/install/cache` и `app/assets/builds/`) вне scope, зафиксирована в брифе как «не входит»
- `bin/rails assets:precompile` в test-окружении корректно подхватывает `jsbundling`/`cssbundling` rake-хуки — стандартное поведение Rails 8.1 + указанных гемов; подтверждено разделом 1.1 и конфигурацией `Gemfile.lock`

## 9. Риски

- **Низкий:** обновление `oven-sh/setup-bun@v2` внесёт breaking change → пин `@v2` защищает от major, патч-версии редко ломают. Если случится — чинится локальным пином коммита
- **Низкий:** CI время вырастет на ~10–30 с → приемлемо, бриф исключает оптимизацию из scope
- **Низкий:** рассинхронизация Bun-версии между `Dockerfile` и `ci.yml` → устранено на уровне архитектуры: единый файл `.bun-version` как source of truth, который читают и `Dockerfile`, и `setup-bun@v2` (через `bun-version-file`). Остаточный риск — ручная правка одного из потребителей в обход `.bun-version`
- **Низкий:** кеширование `~/.bun/install/cache` и `app/assets/builds/` не реализовано → допущение «10–30 с» деградирует при росте зависимостей. Устраняется отдельной задачей #11 (`ci: cache bun install and asset builds`)
