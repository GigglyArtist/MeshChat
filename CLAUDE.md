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
| `Presentation/` | SwiftUI, UIKit, Observation, os, VisionKit, Vision (только `VNBarcodeSymbology`), AVFoundation (только разрешение камеры), CoreImage | CoreData, Network |
| `App/` | всё | — |

Слои общаются только через протоколы из `Domain/Protocols`. Конкретные типы создаются только в `App/` (`AppStartup`, `AppEnvironment`). Во View зависимости передаются через `init`, без `.environment(...)`.

## Swift и конкурентность

- Swift 6 language mode, iOS 17.0+, ноль предупреждений.
- Изменяемое общее состояние — `actor`. ViewModel — `@Observable @MainActor final class`.
- В проекте `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: всё вне `Presentation/` и `App/` помечай `nonisolated` (или делай `actor`). Настройку проекта не меняй.
- `@unchecked Sendable` и `nonisolated(unsafe)` — только с комментарием, почему это безопасно.
- Известные приёмы (ARCHITECTURE.md §17.1):
  - `static let` не-`Sendable` типа → `nonisolated(unsafe) static let` + комментарий; для `Sendable`-типов (`Data`, `String`, `UUID`) `nonisolated(unsafe)` **не** ставить — это предупреждение компилятора;
  - Obj-C-глобалы merge policy → `NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)`;
  - запросы Core Data → `NSFetchRequest<T>(entityName: T.entityName)`, без строковых литералов имён сущностей.
  - `Codable`-типы вне Presentation/App — `nonisolated struct`, иначе conformance станет изолированной на `MainActor` и неизолированный код не сможет кодировать;
  - срезы `Data` сохраняют индексы исходника: индексируй от `startIndex`, наружу отдавай `Data(slice)`;
  - протоколы вне Presentation/App — `nonisolated` на **каждом** требовании; у актора синхронные свойства из протокола — `nonisolated let`;
  - акторы реентерабельны: после каждого `await` перепроверяй состояние (участник мог уйти, сессия — завершиться).

## Стиль

- Первые строки каждого Swift-файла:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 MeshChat contributors
  ```
- Один основной тип на файл, имя файла = имя типа.
- Идентификаторы и коммиты — на английском, `///`-комментарии — на русском. Все протоколы документированы.
- Запрещено: force unwrap и `try!` вне тестов, `print` (только `os.Logger`), синглтоны `static let shared`, сторонние зависимости, `NSManagedObject` вне `Storage/`, тестовые хуки в production-коде (`…ForTesting`) — тесты работают только через публичный API и внедряемые зависимости.
- UI не отказывает молча: не удалось построить картинку/QR — `Logger.error` и видимый текст ошибки на экране.
- Никогда не логируй `roomKey`, `tlsPSK`, `authToken`, пароль. ID, ники и тексты — только с `privacy: .private`.

## Xcode-проект

- Проект использует синхронизируемые папки: новые файлы внутри папки таргета попадают в проект сами. Не создавай группы вручную.
- `project.pbxproj` напрямую **не редактируй** (Xcode держит его открытым, хук блокирует запись). Если задаче нужна новая build setting или capability — остановись и напиши мне: таргет, конфигурация, настройка, значение. После моего подтверждения проверь результат через `xcodebuild -showBuildSettings`.
- `Config/Info.plist` лежит вне папки таргета — не переноси его.

## Сборка и тесты

Таргеты: `MeshChat`, `MeshChatTests`, `MeshChatUITests`. Схема: `MeshChat`.

- Сборка и тесты — через инструменты Xcode (`BuildProject`, `RunAllTests` и т. п.), если они тебе доступны; иначе через `xcodebuild`. В отчёте укажи, чем пользовался.
- Для `xcodebuild` бери любой iPhone из `xcrun simctl list devices available` или `-destination 'generic/platform=iOS Simulator'` для сборки без запуска.
- Проверки настроек (`xcodebuild -showBuildSettings`) симулятор не требуют — их выполняй всегда, когда промпт просит.
- **Фантомные ошибки Xcode.** Если инструменты Xcode или редактор пишут `Cannot find 'X' in scope`, а `xcodebuild` собирает успешно, — это устаревший индекс Xcode. Не переписывай и не переноси код ради него. Напиши об этом в отчёте: лечится через Product → Clean Build Folder (⇧⌘K).

```bash
xcodebuild -scheme MeshChat -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build
xcodebuild -scheme MeshChat -destination 'platform=iOS Simulator,name=<iPhone из simctl>' -derivedDataPath DerivedData test
```

Тесты — Swift Testing (`import Testing`). Сборка и все тесты должны быть зелёными перед каждым коммитом.

## Коммиты (Conventional Commits, ARCHITECTURE.md §17.4)

- Формат: `<type>(<scope>): <summary>` — повелительное наклонение, по-английски, ≤ 72 символа, без точки в конце. В теле при необходимости: что и зачем + `Refs: ARCHITECTURE.md §N`.
- Типы: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `build`, `style`.
- Scopes: `config`, `storage`, `security`, `network`, `protocol`, `session`, `app`, `ui`, `chat`, `history`, `qr`, `architecture`.
- Коммить сам после каждой завершённой фичи, только при зелёной сборке и тестах.
- Перед коммитом: `git status` и `git diff --staged --stat`. Список файлов в индексе должен совпадать с файлами именно этого коммита. Инструмент записи файлов может добавлять их в индекс сам — лишние убирай через `git restore --staged <file>`. Никогда не коммить `xcuserdata/`, `DerivedData/`, `.DS_Store`.
- Не делай `git push`, `--force`, `rebase`, `--amend` уже опубликованных коммитов.
- Нашёл ошибку в уже закоммиченном коде — отдельный коммит `fix(<scope>): …`, не внутри `test(...)` или другого коммита.
- Исправление бага коммитится **вместе** с регрессионным тестом, который без исправления падает.

## Порядок шагов

Каждый коммит должен собираться. Если шаг задачи не компилируется без файла из следующего шага — перенеси этот файл в текущий шаг и укажи это в отчёте.

## Отчёт после задачи (строго по шаблону)

1. **Проверки из промпта** — дословный вывод всех команд, которые промпт просит «вывести в отчёт». Нельзя пересказывать своими словами или пропускать.
2. **Файлы** — созданные, изменённые, удалённые, перемещённые.
3. **Коммиты** — `git log --oneline --decorate` новых коммитов. Сверь с планом коммитов из промпта: если какие-то объединены, разделены или пропущены — перечисли и объясни.
4. **Тег** — вывод `git tag --points-at HEAD`.
5. **Тесты** — **дословно** итоговые строки из вывода `xcodebuild test`: `Executed N tests, with M failures …` (или `Test run with N tests …`, если она есть) и `** TEST SUCCEEDED **`. Ничего не оценивай и не пересчитывай вручную: параметризованный тест считается по числу аргументов. Если есть отключённые (`.disabled`) тесты — перечисли их с причиной.
6. **Отклонения и вопросы** — всё, что сделано не так, как написано в промпте, включая пути к файлам.
7. **Рабочая копия** — вывод `git status --short` в конце задачи. Он должен быть пустым; если нет — объясни каждую строку.
