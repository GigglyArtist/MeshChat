#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 MeshChat contributors
#
# Стресс-проверка MeshChat: N полных прогонов MeshChatTests подряд (по умолчанию 10), ARCHITECTURE.md §16.3.
# Запуск из корня репозитория: bash scripts/stress_meshchat.sh [N]
# Сборка выполняется один раз (build-for-testing), затем N раз test-without-building.

N=${1:-10}
cd "$(dirname "$0")/.." || exit 1
[ -d MeshChat.xcodeproj ] || { echo "Не найден MeshChat.xcodeproj рядом с папкой scripts/"; exit 1; }

LINE=$(xcrun simctl list devices available | grep -m1 -E "^[[:space:]]+iPhone")
UDID=$(echo "$LINE" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
[ -n "$UDID" ] || { echo "Не найден iPhone-симулятор"; exit 1; }
echo "Симулятор: $(echo "$LINE" | sed -E 's/^[[:space:]]+//; s/ \(.*//')"
echo "Коммит:    $(git log --oneline -1)"
[ -z "$(git status --short)" ] || echo "ВНИМАНИЕ: есть незакоммиченные изменения — проверяется рабочая копия, а не коммит"

DD=/tmp/meshchat-stress
echo "Сборка для тестов (1–3 минуты)..."
if ! xcodebuild build-for-testing -scheme MeshChat -destination "id=$UDID" \
     -derivedDataPath "$DD" > /tmp/stress-build.log 2>&1; then
  echo "Сборка не удалась. Хвост лога (/tmp/stress-build.log):"
  grep -E "error:" /tmp/stress-build.log | head -10
  exit 1
fi

PASS=0
for i in $(seq 1 "$N"); do
  RESULT=/tmp/stress-$i.xcresult
  rm -rf "$RESULT"
  START=$(date +%s)
  xcodebuild test-without-building -scheme MeshChat -destination "id=$UDID" \
    -derivedDataPath "$DD" -only-testing:MeshChatTests -resultBundlePath "$RESULT" \
    > /tmp/stress-$i.log 2>&1
  SECS=$(( $(date +%s) - START ))
  # test-without-building печатает «** TEST EXECUTE SUCCEEDED **», поэтому главный критерий — результат из .xcresult
  RES=$(xcrun xcresulttool get test-results summary --path "$RESULT" 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("result"), "{}/{}".format(d.get("passedTests"), d.get("totalTestCount")))' 2>/dev/null)
  if [ "${RES%% *}" = "Passed" ] || grep -qE "\*\* TEST (EXECUTE )?SUCCEEDED \*\*" /tmp/stress-$i.log; then
    PASS=$((PASS + 1))
    echo "run $i: OK (${SECS} с) — прошло ${RES#* }"
  else
    echo "run $i: FAILED (${SECS} с) — лог: /tmp/stress-$i.log"
    FOUND=0
    if xcrun xcresulttool get test-results summary --path "$RESULT" > /tmp/stress-$i.json 2>/dev/null; then
      python3 - "/tmp/stress-$i.json" <<'PY' && FOUND=1
import json, sys
d = json.load(open(sys.argv[1]))
print("   итог: {} | всего {} | прошло {} | упало {} | пропущено {}".format(
    d.get("result"), d.get("totalTestCount"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests")))
fails = d.get("testFailures", [])
for f in fails:
    text = (f.get("failureText") or "").replace("\n", " ")[:220]
    print("   ✗", f.get("testName"), "—", text)
sys.exit(0 if fails else 1)
PY
    fi
    if [ "$FOUND" -eq 0 ]; then
      echo "   (имён упавших тестов нет — ошибки из лога:)"
      grep -E "error:|Testing failed|failed on '|Expectation failed|recorded an issue|crash|Restarting after|exited with" \
        /tmp/stress-$i.log | head -12 | sed 's/^/   /'
    fi
  fi
done

echo "Итог: $PASS из $N зелёных"
[ "$PASS" -eq "$N" ] && echo "Можно ставить тег этапа." || echo "Пришли этот вывод — разберём упавшие тесты."
