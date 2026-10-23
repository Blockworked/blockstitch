#!/usr/bin/env bash
# Usage: qml/tests/run.sh [qmltestrunner]: the module's QML tests, offscreen,
# against qml/Blockstitch laid out as module.json registers it.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(dirname "$here")
runner=${1:-qmltestrunner}
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
mod="$out/com/blockworked/Blockstitch"; mkdir -p "$mod"
cp -R "$root/Blockstitch/." "$mod/"
python3 - "$root/module.json" > "$mod/qmldir" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print("module " + m["uri"])
for f in m["files"]:
    print(("singleton " if f in m["singletons"] else "") + f"{f[:-4]} {m['version']} {f}")
PY
QT_QPA_PLATFORM=offscreen "$runner" -import "$out" -input "$here"
