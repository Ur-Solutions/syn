#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Syn"
BUNDLE_ID="com.trmdy.syn"
PROJECT_PATH="Syn.xcodeproj"
SCHEME="Syn"
CONFIGURATION="Debug"
ENABLE_DEBUG_DYLIB="${SYN_ENABLE_DEBUG_DYLIB:-NO}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
STAGED_APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
CANONICAL_USER_APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
SIGN_IDENTITY="${SYN_CODE_SIGN_IDENTITY:-}"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

source "$ROOT_DIR/script/signing_identity.sh"

build_app() {
  cd "$ROOT_DIR"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "$APP_BUNDLE"

  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(find_default_sign_identity || true)"
  fi

  local xcodebuild_args=(
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    "ENABLE_DEBUG_DYLIB=$ENABLE_DEBUG_DYLIB"
  )

  if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Using code signing identity: $SIGN_IDENTITY"
    xcodebuild_args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY")
  else
    echo "Using project default code signing identity."
  fi

  xcodebuild "${xcodebuild_args[@]}"
}

stage_app() {
  mkdir -p "$(dirname "$STAGED_APP_BUNDLE")"
  if [[ -d "$STAGED_APP_BUNDLE" ]]; then
    /usr/bin/rsync -aE --delete "$APP_BUNDLE/" "$STAGED_APP_BUNDLE/"
  else
    /usr/bin/ditto "$APP_BUNDLE" "$STAGED_APP_BUNDLE"
  fi

  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$STAGED_APP_BUNDLE" >/dev/null 2>&1 || true
  fi

  if [[ "$STAGED_APP_BUNDLE" != "$CANONICAL_USER_APP_BUNDLE" && -d "$CANONICAL_USER_APP_BUNDLE" ]]; then
    /usr/bin/rsync -aE --delete "$STAGED_APP_BUNDLE/" "$CANONICAL_USER_APP_BUNDLE/"
    if [[ -x "$lsregister" ]]; then
      "$lsregister" -f "$CANONICAL_USER_APP_BUNDLE" >/dev/null 2>&1 || true
    fi
  fi
}

open_app() {
  /usr/bin/open -n "$STAGED_APP_BUNDLE"
}

build_app
stage_app

case "$MODE" in
  run)
    open_app
    echo "$APP_NAME launched from $STAGED_APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$STAGED_APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running from $STAGED_APP_BUNDLE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
