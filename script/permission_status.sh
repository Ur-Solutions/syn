#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Syn app binary is missing at $APP_BINARY"
  echo "Run ./script/build_and_run.sh --verify first."
  exit 1
fi

"$APP_BINARY" --syn-permission-status-fixture
