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
  - синхронный `init` актора в режиме `MainActor` по умолчанию становится `@MainActor` → пиши `nonisolated init(...)`;
  - события `AsyncStream` во ViewModel читаются в собственной задаче (`start()` идемпотентен), не в `.task` View;
  - чистые хелперы Presentation (форматирование, склонение) — `nonisolated static func`, чтобы их могли вызывать тесты вне главного актора.
  - замена элемента `NavigationStack` значением того же case (`path = [.chat(new)]`) может не пересоздать экран — `@State` с ViewModel останется старым → у View назначения `.id(<маршрут>)`;
  - если `async`-вызов вернул объект с соединением (комнату), а экран уже закрыт, — сразу закрой этот объект (`leave()`): у комнаты всегда есть владелец (ADR-13).

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

**Тесты со временем** (ARCHITECTURE.md §16.3): в сценариях успеха таймауты конфигурации — секунды; короткие (100–300 мс) — только в тестах самого таймаута; ожидание события — `waitFor(timeout: .seconds(5))`; порядок событий обеспечивает код, а не удача. Зелёный прогон инструментами Xcode стабильность не доказывает.

**Проверка тестов агентом** (§16.3):
- полный набор `MeshChatTests` через `xcodebuild` — **один раз**, на переднем плане (не фоновой задачей), вывод в файл, `-resultBundlePath`;
- упал тест → только его набор (`-only-testing:MeshChatTests/<Suite>`), до 3 повторов, поиск причины, исправление;
- **10 прогонов подряд агент не запускает** — их делает автор скриптом `scripts/stress_meshchat.sh`. Тег этапа агент **не ставит**: автор ставит его после 10 из 10.

## Коммиты (Conventional Commits, ARCHITECTURE.md §17.4)

- Формат: `<type>(<scope>): <summary>` — повелительное наклонение, по-английски, ≤ 72 символа, без точки в конце. В теле при необходимости: что и зачем + `Refs: ARCHITECTURE.md §N`.
- Типы: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`, `build`, `style`.
- Scopes: `config`, `domain`, `storage`, `security`, `network`, `protocol`, `session`, `app`, `ui`, `chat`, `history`, `qr`, `architecture`.
- Коммить сам после каждой завершённой фичи, только при зелёной сборке и тестах.
- Перед коммитом: `git status` и `git diff --staged --stat`. Список файлов в индексе должен совпадать с файлами именно этого коммита. Инструмент записи файлов может добавлять их в индекс сам — лишние убирай через `git restore --staged <file>`. Никогда не коммить `xcuserdata/`, `DerivedData/`, `.DS_Store`.
- Не делай `git push`, `--force`, `rebase`, `--amend` уже опубликованных коммитов.
- Нашёл ошибку в уже закоммиченном коде — отдельный коммит `fix(<scope>): …`, не внутри `test(...)` или другого коммита.
- `fix` — только если меняется поведение приложения (код в `MeshChat/`). Правки только тестов, фейков и тестовых таймаутов — `test(...)`, даже если найдены при стресс-прогоне.
- Исправление бага коммитится **вместе** с регрессионным тестом, который без исправления падает.

## Экономия контекста

Лимит агента конечен — в задаче 07 он закончился посреди проверки.

- Вывод `xcodebuild` **всегда** в файл (`> /tmp/<имя>.log 2>&1`), на экран — только `grep` итоговых строк и упавших тестов. Полные логи не читать.
- Не запускай тесты фоновыми задачами: они обрываются через 10 минут, а опрос их вывода тратит контекст.
- Длинный чат дорог: каждое сообщение заново обрабатывает всю историю. Если задача растянулась, лучше закончить шаг, закоммитить и попросить автора открыть новый чат.
- Не перечитывай большие файлы целиком, если нужен один фрагмент: `grep -n`, затем чтение нужных строк.

## Порядок шагов

Каждый коммит должен собираться. Если шаг задачи не компилируется без файла из следующего шага — перенеси этот файл в текущий шаг и укажи это в отчёте.

## Отчёт после задачи (строго по шаблону)

1. **Проверки из промпта** — дословный вывод всех команд, которые промпт просит «вывести в отчёт». Нельзя пересказывать своими словами или пропускать.
2. **Файлы** — созданные, изменённые, удалённые, перемещённые.
3. **Коммиты** — `git log --oneline --decorate` новых коммитов. Сверь с планом коммитов из промпта: если какие-то объединены, разделены или пропущены — перечисли и объясни.
4. **Тег** — вывод `git tag --points-at HEAD` (тег этапа ставит автор после стресс-прогона; если промпт не просит иное — здесь пусто).
5. **Тесты** — запусти `xcodebuild test … -resultBundlePath /tmp/meshchat-result.xcresult` (папку перед этим удали) и выведи **дословно** `** TEST SUCCEEDED **` и счётчики из `xcrun xcresulttool get test-results summary --path /tmp/meshchat-result.xcresult` (`totalTestCount`, `passedTests`, `failedTests`, `skippedTests`). Ничего не пересчитывай вручную. Если есть отключённые (`.disabled`) тесты — перечисли их с причиной.
6. **Отклонения и вопросы** — всё, что сделано не так, как написано в промпте, включая пути к файлам. **Ответ на каждый вопрос и результат каждого эксперимента**, которые промпт просит, — обязательно, даже если ответ «не делал, потому что…».
7. **Рабочая копия** — вывод `git status --short` в конце задачи. Он должен быть пустым; если нет — объясни каждую строку.
