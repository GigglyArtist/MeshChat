#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 MeshChat contributors
#
# Полная проверка проекта MeshChat (ARCHITECTURE.md §16.2.1).
# Запуск из корня репозитория: bash scripts/verify_meshchat.sh
cd "$(dirname "$0")/.." || exit 1
[ -d MeshChat.xcodeproj ] || { echo "Не найден MeshChat.xcodeproj рядом с папкой scripts/"; exit 1; }

echo "=== 1. Настройки сборки ==="
for t in MeshChat MeshChatTests MeshChatUITests; do
  echo "-- $t"
  xcodebuild -showBuildSettings -project MeshChat.xcodeproj -target "$t" 2>/dev/null \
    | grep -E "^[[:space:]]*(SWIFT_VERSION|IPHONEOS_DEPLOYMENT_TARGET|INFOPLIST_FILE) ="
done

echo "=== 2. Чистая сборка: предупреждения Swift (ожидается пусто) ==="
rm -rf /tmp/meshchat-check
xcodebuild -scheme MeshChat -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/meshchat-check build > /tmp/meshchat-build.log 2>&1
grep -q "BUILD SUCCEEDED" /tmp/meshchat-build.log && echo "BUILD SUCCEEDED" || echo "BUILD FAILED — см. /tmp/meshchat-build.log"
grep -E "\.swift:[0-9]+:[0-9]+: warning:" /tmp/meshchat-build.log | sed "s|$PWD/||" | sort -u

echo "=== 3. Info.plist собранного приложения ==="
plutil -p /tmp/meshchat-check/Build/Products/Debug-iphonesimulator/MeshChat.app/Info.plist \
  | grep -E "_meshchat|NSLocalNetworkUsageDescription|NSCameraUsageDescription"

echo "=== 4. Контрольные значения в тестах (ожидается ≥ 1 в каждой строке) ==="
grep -c "daaa69f872987f5f5d97fe64b7ab3ebabd3f6865f149b8db41413404d0639798" MeshChatTests/Security/RoomCredentialsTests.swift
grep -c "2qpp+HKYf19dl/5kt6s+ur0/aGXxSbjbQUE0BNBjl5g=" MeshChatTests/Domain/RoomInviteTests.swift

if [ -f MeshChatTests/Network/PacketCodecTests.swift ]; then
  echo "-- контрольные кадры протокола (ожидается ≥ 1 в каждой строке):"
  grep -c "000000d2\|0x00, 0x00, 0x00, 0xd2\|0xD2\|210" MeshChatTests/Network/PacketCodecTests.swift
  grep -c "ZnHO5AlEPIxMOZlaWlPxkaBMMYfv3NvyAi29ppmbbhk=" MeshChatTests/Network/PacketCodecTests.swift
fi

echo "=== 5. Тесты MeshChatTests (2–4 минуты) ==="
LINE=$(xcrun simctl list devices available | grep -m1 -E "^[[:space:]]+iPhone")
UDID=$(echo "$LINE" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
echo "Симулятор: $(echo "$LINE" | sed -E 's/^[[:space:]]+//; s/ \(.*//') ($UDID)"
RESULT=/tmp/meshchat-result.xcresult
rm -rf "$RESULT"
xcodebuild test -scheme MeshChat -destination "id=$UDID" -derivedDataPath /tmp/meshchat-check \
  -only-testing:MeshChatTests -resultBundlePath "$RESULT" > /tmp/meshchat-test.log 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" /tmp/meshchat-test.log || { echo "Итог не найден — хвост лога:"; tail -25 /tmp/meshchat-test.log; }
if xcrun xcresulttool get test-results summary --path "$RESULT" > /tmp/meshchat-summary.json 2>/dev/null; then
  python3 - <<'PY'
import json
d = json.load(open("/tmp/meshchat-summary.json"))
print("Итог: {} | всего {} | прошло {} | упало {} | пропущено {}".format(
    d.get("result"), d.get("totalTestCount"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests")))
print("-- упавшие тесты (ожидается пусто):")
for f in d.get("testFailures", []):
    print("  ", f.get("testName"), "—", (f.get("failureText") or "")[:200])
PY
else
  echo "-- упавшие тесты (ожидается пусто):"
  grep -E "failed on '|Expectation failed|recorded an issue" /tmp/meshchat-test.log | head -15
fi
echo "-- отключённые тесты (ожидается пусто):"
grep -rn "\.disabled" MeshChatTests

echo "=== 6. История и рабочая копия ==="
git log --oneline --decorate -15
echo "-- незакоммиченное (ожидается пусто):"
git status --short
