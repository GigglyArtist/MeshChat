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
| `Presentation/` | SwiftUI, UIKit, Observation, VisionKit, CoreImage | CoreData, Network |
| `App/` | всё | — |

Слои общаются только через протоколы из `Domain/Protocols`. Конкретные типы создаются только в `App/AppEnvironment.swift`.

## Swift и конкурентность

- Swift 6 language mode, iOS 17.0+, ноль предупреждений.
- Изменяемое общее состояние — `actor`. ViewModel — `@Observable @MainActor final class`.
- Если в build settings `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: всё вне `Presentation/` и `App/` помечай `nonisolated` (или делай `actor`). Настройку проекта не меняй.
- `@unchecked Sendable` — только с комментарием, почему это безопасно.

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
- `project.pbxproj` правь только если задача этого прямо требует, точечно, и проверяй результат через `xcodebuild -showBuildSettings`.
- `Config/Info.plist` лежит вне папки таргета — не переноси его.

## Сборка и тесты

```bash
xcrun simctl list devices available            # выбери доступный iPhone-симулятор
xcodebuild -scheme <App> -destination 'platform=iOS Simulator,name=<iPhone>' -derivedDataPath DerivedData build
xcodebuild -scheme <App> -destination 'platform=iOS Simulator,name=<iPhone>' -derivedDataPath DerivedData test
```

Тесты — Swift Testing (`import Testing`). Сборка и все тесты должны быть зелёными перед каждым коммитом.

## Коммиты (Conventional Commits, ARCHITECTURE.md §17.4)

- Формат: `<type>(<scope>): <summary>` — повелительное наклонение, по-английски, ≤ 72 символа, без точки в конце. В теле при необходимости: что и зачем + `Refs: ARCHITECTURE.md §N`.
- Типы: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `build`, `style`.
- Scopes: `config`, `storage`, `security`, `network`, `protocol`, `session`, `app`, `ui`, `chat`, `history`, `qr`, `architecture`.
- Коммить сам после каждой завершённой фичи, только при зелёной сборке и тестах.
- Перед коммитом: `git status` и `git diff --staged`. Добавляй файлы явно, без `xcuserdata/`, `DerivedData/`, `.DS_Store`.
- Не делай `git push`, `--force`, `rebase`, `--amend` уже опубликованных коммитов.

## Отчёт после задачи

1. Список созданных и изменённых файлов.
2. `git log --oneline` новых коммитов.
3. Итог сборки и тестов (сколько тестов, все ли зелёные).
4. Отклонения от задачи и открытые вопросы, если есть.
