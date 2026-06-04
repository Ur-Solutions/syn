#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
ACTION="${1:-suffix-r}"
WORK_DIR="$ROOT_DIR/build/live-hotkey-fixture"
LOG_PATH="$WORK_DIR/$ACTION-actions.log"
EVENT_LOG_PATH="$WORK_DIR/$ACTION-events.log"
CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-live-hotkey-$ACTION.png"
CAFFEINATE_PID=""

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/ui-captures"
rm -f "$LOG_PATH" "$EVENT_LOG_PATH"

case "$ACTION" in
  suffix-r|medium-suffix-r|slow-suffix-r|held-r|fast-held-r|long-held-r|repeat)
    ;;
  *)
    echo "usage: $0 [suffix-r|medium-suffix-r|slow-suffix-r|held-r|fast-held-r|long-held-r|repeat]" >&2
    exit 2
    ;;
esac

cleanup() {
  if [[ -n "$CAFFEINATE_PID" ]]; then
    kill "$CAFFEINATE_PID" >/dev/null 2>&1 || true
    wait "$CAFFEINATE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

/usr/bin/caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
CAFFEINATE_PID=$!

./script/build_and_run.sh --verify >/tmp/syn-live-hotkey-build.log
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

/usr/bin/open -n "$STAGED_APP_BUNDLE" --args \
  --syn-show-main-window \
  --syn-hotkey-observer \
  --syn-hotkey-action-log "$LOG_PATH" \
  --syn-hotkey-event-log "$EVENT_LOG_PATH"

for _ in {1..30}; do
  if pgrep -x "$APP_NAME" >/dev/null; then
    break
  fi
  sleep 0.2
done

sleep 1
/usr/bin/swift script/post_syn_hotkey_sequence.swift "$ACTION"

for _ in {1..60}; do
  if [[ -s "$LOG_PATH" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$LOG_PATH" ]]; then
  SYN_UI_ATTACH_ONLY=1 ./script/capture_syn_ui.sh "$CAPTURE_PATH" >/dev/null || true
  echo "SYN_LIVE_HOTKEY_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_REASON=no-hotkey-action"
  echo "SYN_LIVE_HOTKEY_CAPTURE=$CAPTURE_PATH"
  echo "SYN_LIVE_HOTKEY_EVENT_LOG=$EVENT_LOG_PATH"
  exit 1
fi

first_action="$(sed -n '1p' "$LOG_PATH")"
expected="picker"
if [[ "$ACTION" == "repeat" || "$ACTION" == "slow-suffix-r" ]]; then
  expected="repeat"
fi

if [[ "$expected" == "picker" ]]; then
  # Picker is only proven to win after repeat's brief suffix grace has elapsed.
  sleep 1.2
else
  sleep 0.5
fi

action_count="$(wc -l < "$LOG_PATH" | tr -d '[:space:]')"
all_actions="$(tr '\n' ',' < "$LOG_PATH" | sed 's/,$//')"

SYN_UI_ATTACH_ONLY=1 ./script/capture_syn_ui.sh "$CAPTURE_PATH"

if [[ "$first_action" != "$expected" ]]; then
  echo "SYN_LIVE_HOTKEY_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_EXPECTED=$expected"
  echo "SYN_LIVE_HOTKEY_ACTION=$first_action"
  echo "SYN_LIVE_HOTKEY_ACTIONS=$all_actions"
  echo "SYN_LIVE_HOTKEY_ACTION_COUNT=$action_count"
  echo "SYN_LIVE_HOTKEY_LOG=$LOG_PATH"
  echo "SYN_LIVE_HOTKEY_EVENT_LOG=$EVENT_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_CAPTURE=$CAPTURE_PATH"
  exit 1
fi

if [[ "$action_count" != "1" ]]; then
  echo "SYN_LIVE_HOTKEY_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_REASON=unexpected-extra-actions"
  echo "SYN_LIVE_HOTKEY_EXPECTED=$expected"
  echo "SYN_LIVE_HOTKEY_ACTIONS=$all_actions"
  echo "SYN_LIVE_HOTKEY_ACTION_COUNT=$action_count"
  echo "SYN_LIVE_HOTKEY_LOG=$LOG_PATH"
  echo "SYN_LIVE_HOTKEY_EVENT_LOG=$EVENT_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_CAPTURE=$CAPTURE_PATH"
  exit 1
fi

echo "SYN_LIVE_HOTKEY_FIXTURE=passed"
echo "SYN_LIVE_HOTKEY_ACTION=$first_action"
echo "SYN_LIVE_HOTKEY_ACTION_COUNT=$action_count"
echo "SYN_LIVE_HOTKEY_LOG=$LOG_PATH"
echo "SYN_LIVE_HOTKEY_EVENT_LOG=$EVENT_LOG_PATH"
echo "SYN_LIVE_HOTKEY_CAPTURE=$CAPTURE_PATH"
