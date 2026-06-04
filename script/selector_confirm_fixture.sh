#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
MODE="${1:-region}"
WORK_DIR="$ROOT_DIR/build/selector-confirm-fixture"
LOG_PATH="$WORK_DIR/$MODE-confirm.log"
CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-selector-confirm-$MODE-failure.png"
FIXTURE_WINDOW_PID=""

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/ui-captures"
rm -f "$LOG_PATH"

cleanup() {
  if [[ -n "$FIXTURE_WINDOW_PID" ]]; then
    kill "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
    wait "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

./script/build_and_run.sh --verify >/tmp/syn-selector-confirm-build.log
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

selector_arg=""
window_title=""
case "$MODE" in
  region)
    selector_arg="--syn-show-region-selector-fixture"
    window_title="Syn Region Selection"
    ;;
  selectedWindow|window)
    MODE="selectedWindow"
    selector_arg="--syn-show-window-selector-fixture"
    window_title="Syn Window Selection Target"
    /usr/bin/swift script/selection_fixture_window.swift >/tmp/syn-selector-confirm-window.log 2>&1 &
    FIXTURE_WINDOW_PID=$!
    sleep 1
    ;;
  *)
    echo "usage: $0 [region|selectedWindow]" >&2
    exit 2
    ;;
esac

/usr/bin/open -n "$STAGED_APP_BUNDLE" --args \
  "$selector_arg" \
  --syn-selector-confirm-observer \
  --syn-selector-confirm-log "$LOG_PATH"

for _ in {1..40}; do
  if SYN_UI_WINDOW_TITLE="$window_title" /usr/bin/swift -e 'import CoreGraphics; import Foundation; let title = ProcessInfo.processInfo.environment["SYN_UI_WINDOW_TITLE"] ?? ""; let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []; let found = list.contains { ($0[kCGWindowOwnerName as String] as? String) == "Syn" && (($0[kCGWindowName as String] as? String) ?? "") == title }; exit(found ? 0 : 1)' 2>/dev/null; then
    break
  fi
  sleep 0.2
done

for _ in {1..50}; do
  if [[ -s "$LOG_PATH" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$LOG_PATH" ]]; then
  SYN_UI_ATTACH_ONLY=1 SYN_UI_WINDOW_TITLE="$window_title" ./script/capture_syn_ui.sh "$CAPTURE_PATH" >/tmp/syn-selector-confirm-capture.log || true
  echo "SYN_SELECTOR_CONFIRM_FIXTURE=failed"
  echo "SYN_SELECTOR_CONFIRM_MODE=$MODE"
  echo "SYN_SELECTOR_CONFIRM_REASON=no-confirm-log"
  echo "SYN_SELECTOR_CONFIRM_CAPTURE=$CAPTURE_PATH"
  exit 1
fi

confirmed="$(sed -n '1p' "$LOG_PATH")"
case "$MODE" in
  region)
    if [[ "$confirmed" != region* ]]; then
      echo "SYN_SELECTOR_CONFIRM_FIXTURE=failed"
      echo "SYN_SELECTOR_CONFIRM_EXPECTED=region"
      echo "SYN_SELECTOR_CONFIRM_VALUE=$confirmed"
      exit 1
    fi
    ;;
  selectedWindow)
    if [[ "$confirmed" != selectedWindow* ]]; then
      echo "SYN_SELECTOR_CONFIRM_FIXTURE=failed"
      echo "SYN_SELECTOR_CONFIRM_EXPECTED=selectedWindow"
      echo "SYN_SELECTOR_CONFIRM_VALUE=$confirmed"
      exit 1
    fi
    ;;
esac

echo "SYN_SELECTOR_CONFIRM_FIXTURE=passed"
echo "SYN_SELECTOR_CONFIRM_MODE=$MODE"
echo "SYN_SELECTOR_CONFIRM_VALUE=$confirmed"
echo "SYN_SELECTOR_CONFIRM_LOG=$LOG_PATH"
