# План реализации: Propshaft::MissingAssetError в CI-тестах

**Issue:** #9
**Спецификация:** [spec.md](./spec.md) (APPROVED 2026-04-19)
**Бриф:** [brief.md](./brief.md)
**Follow-up:** #11 (кеширование — вне scope)

## Scope

Три файла:

1. `.bun-version` — новый, корень репозитория
2. `Dockerfile` — замена хардкода `BUN_VERSION=1.3.5` на чтение из `.bun-version`
3. `.github/workflows/ci.yml` — 3 новых шага в job `test`

Код приложения, спеки, `config/environments/test.rb`, `config/initializers/assets.rb`, `bun.config.js`, `package.json`, `bun.lock` — не трогаем.

Зависимости этапа сборки (не модифицируются, но от них зависит корректность precompile):

- `bun.config.js` — конфиг, на который ссылается `package.json:build` (`bun bun.config.js`)
- `package.json` + `bun.lock` — фронтенд-зависимости (`@tailwindcss/cli` и др.)

## Новые гемы / зависимости

Нет. Только добавление GitHub Action `oven-sh/setup-bun@v2` в workflow.

`.dockerignore` проверен (`/Users/dniman/Projects/.../.dockerignore`) — `.bun-version` под ignore не попадает, `COPY .bun-version ./` в Dockerfile сработает.

## Детальные изменения

### Шаг 1. Создать `.bun-version`

Файл в корне репозитория с единственной строкой:

```
1.3.5
```

Обоснование: single source of truth для версии Bun (резолвит риск рассинхронизации Dockerfile ↔ ci.yml, §9 спеки).

### Шаг 2. Обновить `Dockerfile`

**Цель:** читать версию Bun из `.bun-version`, при этом сохранить ортогональность cache-слоёв (смена Bun-версии не должна инвалидировать gem-install слой).

**Текущее состояние** (релевантный фрагмент, строки 38-54):

```dockerfile
ENV BUN_INSTALL=/usr/local/bun
ENV PATH=/usr/local/bun/bin:$PATH
ARG BUN_VERSION=1.3.5
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v${BUN_VERSION}"

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Install node modules
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile
```

**После:** блок установки Bun переносится вниз, непосредственно перед установкой node-модулей:

```dockerfile
# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Install Bun and node modules
ENV BUN_INSTALL=/usr/local/bun
ENV PATH=/usr/local/bun/bin:$PATH
COPY .bun-version ./
RUN curl -fsSL https://bun.sh/install | bash -s -- "bun-v$(cat .bun-version)"
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile
```

Детали:
- `ARG BUN_VERSION=1.3.5` убирается — источник версии теперь `.bun-version`
- Блок Bun-install перенесён ниже gem-install: смена `.bun-version` не инвалидирует слой `bundle install` (ортогональность cache-слоёв; ревью этапа 6 — M2)
- Порядок внутри нового блока: `ENV` → `COPY .bun-version` → установка Bun → `COPY package.json bun.lock*` → `bun install`. Это даёт правильную гранулярность инвалидации: смена только `package.json`/`bun.lock` не инвалидирует слой установки Bun-бинаря
- `COPY .bun-version ./` выполняется в build-stage (рабочая директория `/rails`)
- Финальный runtime-stage не меняется (`COPY . .` на строке 57 утянет `.bun-version` вместе с остальным кодом; для runtime не используется)

### Шаг 3. Обновить `.github/workflows/ci.yml`

Добавить три шага в job `test` (строки 76-89 текущего файла) между `Set up Ruby` и `Prepare database`:

**Текущий фрагмент:**

```yaml
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Prepare database
        run: bin/rails db:prepare
```

**После:**

```yaml
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

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
          SECRET_KEY_BASE_DUMMY: "1"

      - name: Prepare database
        run: bin/rails db:prepare
```

Детали:
- Точка вставки: до `db:prepare`, чтобы ошибка сборки ассетов всплывала раньше и давала быстрый фидбек
- `bun-version-file: .bun-version` — нативная поддержка в `setup-bun@v2`
- `RAILS_ENV: test` на уровне шага — явность (job-level `env` уже задаёт `RAILS_ENV: test`, но явное дублирование снижает риск регрессии при будущих правках)
- `SECRET_KEY_BASE_DUMMY: "1"` — преэмптивная защита от требования `SECRET_KEY_BASE` при загрузке Rails-окружения для precompile. Тот же паттерн используется в `Dockerfile:64`. Добавлен сразу, а не как «fallback на случай если упадёт» (ревью этапа 6 — M3)

## Порядок работ

1. Создать `.bun-version`
2. Обновить `Dockerfile` (перенос блока Bun-install вниз + замена `ARG` на `COPY .bun-version`)
3. Обновить `.github/workflows/ci.yml` (3 новых шага)
4. **Локальная проверка (baseline-воспроизведение бага):**
   - `rm -f app/assets/builds/application.js app/assets/builds/application.css`
   - `bundle exec rspec` — **должен упасть** с `Propshaft::MissingAssetError: application.js`; количество падений сопоставить с §1.4 спеки (21 тест)
   - Если падения не воспроизвелись — STOP, диагностика причины прежде чем продолжать (возможно, набор тестов изменился; зафиксировать новый baseline)
5. **Локальная проверка (фикс работает):**
   - `SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile` в чистом окружении (без подхвата dev-only env)
   - Убедиться: файлы появились в `app/assets/builds/application.js` и `application.css`
   - `bundle exec rspec` — все тесты зелёные
6. **Docker-проверка** (sanity check для `.bun-version` в prod-пути):
   - `docker build -t testops:local .` — сборка до конца
   - Образ успешно собирается, `bun-v1.3.5` устанавливается
7. **CI-проверка:**
   - Commit + push ветки `features/009-fix-ci-propshaft-assets`
   - Убедиться в UI GitHub Actions: job `test` зелёный
   - Сравнить список 21 ранее падавшего теста (§1.4 spec) — все `pass`
8. **PR:** ссылка на issue #9 и на follow-up #11 в описании

### Rollback

Все изменения аддитивны и изолированы в трёх файлах. Откат — `git revert` коммита/мержа PR; никаких миграций данных или состояния инфраструктуры за собой не тянет. CI после revert возвращается к предыдущему (красному) состоянию, прод-путь (Dockerfile deploy) — к хардкоду `BUN_VERSION=1.3.5`.

## Тестовая стратегия

**Unit / integration / system:** новых тестов не добавляется.

**Обоснование отсутствия новых тестов:**

- Изменения затрагивают только `.github/workflows/ci.yml`, `Dockerfile`, `.bun-version`. Application code и существующие specs не модифицируются
- CI-конфиг верифицируется самим CI-прогоном (шаг 7 «Порядок работ»): если шаги `Set up Bun` / `Install JS dependencies` / `Precompile assets` работают некорректно, job `test` падает, и это наблюдаемо в GitHub Actions UI
- Корректность `Dockerfile`-правок верифицируется локальным `docker build` (шаг 6)
- Писать unit-тест на YAML workflow или Dockerfile технически возможно (например, `act`, `dockerfilelint`), но это несоразмерная фичи сложность: один разовый инфраструктурный фикс, который либо работает в CI, либо нет — промежуточных состояний нет

**Что верифицируется существующим test suite:**

| Уровень | Набор тестов | Ожидание |
|---|---|---|
| Baseline (до фикса, локально) | 21 спек из §1.4 спеки | **Падают** с `Propshaft::MissingAssetError` (шаг 4 плана) |
| После фикса (локально) | Полный `bundle exec rspec` (59 тестов) | Все `pass` (шаг 5 плана) |
| После фикса (CI) | Job `test` в GitHub Actions | Exit 0, все 21 ранее падавших спека `pass`, остальные 38 без регрессий (шаг 7 плана) |

**Определение регрессии (из §6 критерий 2 спеки):** тест, проходивший до PR, падает после мержа. Время выполнения job и warnings в CI-логе — вне acceptance criteria.

**Что сознательно не покрыто:**

- Тест на конкретную версию Bun (`1.3.5`) — версия зафиксирована в `.bun-version` и используется и `Dockerfile`, и `setup-bun@v2`; расхождение невозможно by design (single source of truth)
- Тест на корректность `bun run build` — это ответственность jsbundling-rails rake-хука и стандартного Rails-контракта `assets:precompile`; дублировать его не нужно
- Тест на cache-поведение Docker-слоёв — косметическое улучшение (M2 из ревью), не влияет на корректность сборки

## Критерии завершения

- [ ] `.bun-version` создан, содержит `1.3.5`
- [ ] `Dockerfile` читает версию из `.bun-version`, `docker build` проходит
- [ ] `.github/workflows/ci.yml` содержит 3 новых шага в нужном порядке
- [ ] Локально: `bundle exec rspec` проходит после `rm -f app/assets/builds/*` + `rails assets:precompile`
- [ ] CI: job `test` зелёный, все 21 ранее падавший тест проходят
- [ ] Других ранее зелёных тестов не упало
- [ ] PR открыт, в описании: ссылка на #9, упомянут follow-up #11

## Риски реализации

| Риск | Вероятность | Mitigation |
|---|---|---|
| `assets:precompile` в `RAILS_ENV=test` требует `SECRET_KEY_BASE` | устранено | `SECRET_KEY_BASE_DUMMY: "1"` добавлен в `env:` шага `Precompile assets` преэмптивно (как в `Dockerfile:64`); ревью этапа 6 — M3 |
| `setup-bun@v2` не распознаёт `bun-version-file` | очень низкая | Официально поддерживается с v2 (доки oven-sh/setup-bun). Fallback: явный `bun-version: $(cat .bun-version)` через `env-file` или напрямую `bun-version: 1.3.5` с комментарием |
| `docker build` ломается из-за `.bun-version` не в нужной рабочей директории | низкая | `WORKDIR /rails` уже задан в Dockerfile:15. `COPY .bun-version ./` положит файл в `/rails/.bun-version` |
| Новые тесты добавились после commit `095896a` (21 failing baseline) | низкая | При расхождении — зафиксировать новый baseline в PR-описании и убедиться что все зелёные |

## Вне scope (из брифа и deferred)

- Кеширование Bun и ассетов (issue #11)
- SHA-pinning third-party actions
- Оптимизация времени CI
- Изменения кода приложения, тестов, test-конфигурации
