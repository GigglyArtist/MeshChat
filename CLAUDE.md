# CLAUDE.md — правила для ИИ-агента в проекте MeshChat

## Проект

MeshChat — офлайн-мессенджер для iOS: SwiftUI + Core Data + Network.framework (Bonjour, `NWListener`, `NWConnection`), 1 хост + до 4 клиентов, без интернета. Open source, GPL-3.0-or-later. Курсовой проект.

## Источник истины

- `ARCHITECTURE.md` — перед каждой задачей прочитай разделы, указанные в промпте. Код обязан ему соответствовать: имена типов, протоколы, схема данных, форматы пакетов, таймауты.
- Если задача противоречит `ARCHITECTURE.md` или требует решения, которого там нет, — остановись и спроси. Не импровизируй.
- Делай только то, что сказано в текущей задаче. Никаких «заодно поправил».

## Слои (ARCHITECTURE.md §3)

| Папка | Можно `import` | Нельзя `import` |
|---|---|---|
| `Domain/` | Foundation | SwiftUI, CoreData, Network, Security, CryptoKit |
| `Security/` | Foundation, Security, CryptoKit | SwiftUI, CoreData, Network |
| `Storage/` | Foundation, CoreData | SwiftUI, Network |
| `Network/` | Foundation, Network, CryptoKit, Security, os | SwiftUI, CoreData |
| `Application/` | Foundation, os | SwiftUI, CoreData, Network |
| `Presentation/` | SwiftUI, UIKit, Observation, VisionKit, AVFoundation (только разрешение камеры), CoreImage | CoreData, Network |
| `App/` | всё | — |

Слои общаются только через протоколы из `Domain/Protocols`. Конкретные типы создаются только в `App/` (`AppStartup`, `AppEnvironment`). Во View зависимости передаются через `init`, без `.environment(...)`.

## Swift и конкурентность

- Swift 6 language mode, iOS 17.0+, ноль предупреждений.
- Изменяемое общее состояние — `actor`. ViewModel — `@Observable @MainActor final class`.
- В проекте `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: всё вне `Presentation/` и `App/` помечай `nonisolated` (или делай `actor`). Настройку проекта не меняй.
- `@unchecked Sendable` и `nonisolated(unsafe)` — только с комментарием, почему это безопасно.
- Известные приёмы (ARCHITECTURE.md §17.1):
  - `static let` не-`Sendable` типа → `nonisolated(unsafe) static let` + комментарий;
  - Obj-C-глобалы merge policy → `NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)`;
  - запросы Core Data → `NSFetchRequest<T>(entityName: T.entityName)`, без строковых литералов имён сущностей.

## Стиль

- Первые строки каждого Swift-файла:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 MeshChat contributors
  ```
- Один основной тип на файл, имя файла = имя типа.
- Идентификаторы и коммиты — на английском, `///`-комментарии — на русском. Все протоколы документированы.
- Запрещено: force unwrap и `try!` вне тестов, `print` (только `os.Logger`), синглтоны `static let shared`, сторонние зависимости, `NSManagedObject` вне `Storage/`.
- Никогда не логируй `roomKey`, `tlsPSK`, `authToken`, пароль. ID, ники и тексты — только с `privacy: .private`.

## Xcode-проект

- Проект использует синхронизируемые папки: новые файлы внутри папки таргета попадают в проект сами. Не создавай группы вручную.
- `project.pbxproj` напрямую **не редактируй** (Xcode держит его открытым, хук блокирует запись). Если задаче нужна новая build setting или capability — остановись и напиши мне: таргет, конфигурация, настройка, значение. После моего подтверждения проверь результат через `xcodebuild -showBuildSettings`.
- `Config/Info.plist` лежит вне папки таргета — не переноси его.

## Сборка и тесты

Таргеты: `MeshChat`, `MeshChatTests`, `MeshChatUITests`. Схема: `MeshChat`. Симулятор по умолчанию: `iPhone 16 Plus` (если его нет — любой доступный из `xcrun simctl list devices available`).

```bash
xcodebuild -scheme MeshChat -destination 'platform=iOS Simulator,name=iPhone 16 Plus' -derivedDataPath DerivedData build
xcodebuild -scheme MeshChat -destination 'platform=iOS Simulator,name=iPhone 16 Plus' -derivedDataPath DerivedData test
```

Тесты — Swift Testing (`import Testing`). Сборка и все тесты должны быть зелёными перед каждым коммитом.

## Коммиты (Conventional Commits, ARCHITECTURE.md §17.4)

- Формат: `<type>(<scope>): <summary>` — повелительное наклонение, по-английски, ≤ 72 символа, без точки в конце. В теле при необходимости: что и зачем + `Refs: ARCHITECTURE.md §N`.
- Типы: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `build`, `style`.
- Scopes: `config`, `storage`, `security`, `network`, `protocol`, `session`, `app`, `ui`, `chat`, `history`, `qr`, `architecture`.
- Коммить сам после каждой завершённой фичи, только при зелёной сборке и тестах.
- Перед коммитом: `git status` и `git diff --staged --stat`. Список файлов в индексе должен совпадать с файлами именно этого коммита. Инструмент записи файлов может добавлять их в индекс сам — лишние убирай через `git restore --staged <file>`. Никогда не коммить `xcuserdata/`, `DerivedData/`, `.DS_Store`.
- Не делай `git push`, `--force`, `rebase`, `--amend` уже опубликованных коммитов.

## Порядок шагов

Каждый коммит должен собираться. Если шаг задачи не компилируется без файла из следующего шага — перенеси этот файл в текущий шаг и укажи это в отчёте.

## Отчёт после задачи (строго по шаблону)

1. **Проверки из промпта** — дословный вывод всех команд, которые промпт просит «вывести в отчёт». Нельзя пересказывать своими словами или пропускать.
2. **Файлы** — созданные, изменённые, удалённые, перемещённые.
3. **Коммиты** — `git log --oneline --decorate` новых коммитов. Сверь с планом коммитов из промпта: если какие-то объединены, разделены или пропущены — перечисли и объясни.
4. **Тег** — вывод `git tag --points-at HEAD`.
5. **Тесты** — сколько всего, сколько новых, все ли зелёные.
6. **Отклонения и вопросы** — всё, что сделано не так, как написано в промпте, включая пути к файлам.
