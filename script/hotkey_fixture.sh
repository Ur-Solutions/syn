#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/Syn.app}"
STAGED_APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/Syn"

cd "$ROOT_DIR"

./script/build_and_run.sh --verify >/tmp/syn-hotkey-fixture-build.log
pkill -x Syn >/dev/null 2>&1 || true
sleep 0.3

if [[ ! -x "$STAGED_APP_BINARY" ]]; then
  echo "Syn staged app binary was not found at $STAGED_APP_BINARY" >&2
  exit 1
fi

"$STAGED_APP_BINARY" --syn-hotkey-fixture
