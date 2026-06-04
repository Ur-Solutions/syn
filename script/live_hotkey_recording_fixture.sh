#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
TRIGGER="${1:-picker}"
MODE="${2:-selectedWindow}"
DURATION="${3:-1.0}"
PROCESS_PACKET="${4:-}"
SEQUENCE="${SYN_HOTKEY_SEQUENCE:-}"
if [[ -z "$SEQUENCE" ]]; then
  if [[ "$TRIGGER" == "picker" ]]; then
    SEQUENCE="suffix-r"
  else
    SEQUENCE="repeat"
  fi
fi
WORK_DIR="$ROOT_DIR/build/live-hotkey-recording-fixture"
LOG_PATH="$WORK_DIR/$TRIGGER-$MODE-$SEQUENCE-recording.log"
ACTION_LOG_PATH="$WORK_DIR/$TRIGGER-$MODE-$SEQUENCE-actions.log"
EVENT_LOG_PATH="$WORK_DIR/$TRIGGER-$MODE-$SEQUENCE-events.log"
CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-live-hotkey-recording-$TRIGGER-$MODE-$SEQUENCE-failure.png"
HUD_CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-live-hotkey-recording-$TRIGGER-$MODE-$SEQUENCE-hud.png"
FIXTURE_WINDOW_PID=""
CAFFEINATE_PID=""
EXTRA_APP_ARGS=()

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/ui-captures"
rm -f "$LOG_PATH" "$ACTION_LOG_PATH" "$EVENT_LOG_PATH" "$HUD_CAPTURE_PATH"

cleanup() {
  if [[ -n "$CAFFEINATE_PID" ]]; then
    kill "$CAFFEINATE_PID" >/dev/null 2>&1 || true
    wait "$CAFFEINATE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$FIXTURE_WINDOW_PID" ]]; then
    kill "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
    wait "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

/usr/bin/caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
CAFFEINATE_PID=$!

case "$TRIGGER" in
  picker|repeat)
    ;;
  *)
    echo "usage: $0 [picker|repeat] [selectedWindow|region|smartRegion|screen|allScreens|activeWindowFollow] [duration-seconds] [--process]" >&2
    exit 2
    ;;
esac

case "$SEQUENCE" in
  suffix-r|medium-suffix-r|held-r|fast-held-r|long-held-r)
    if [[ "$TRIGGER" != "picker" ]]; then
      echo "SYN_HOTKEY_SEQUENCE=$SEQUENCE can only be used with trigger=picker." >&2
      exit 2
    fi
    ;;
  repeat|slow-suffix-r)
    if [[ "$TRIGGER" != "repeat" ]]; then
      echo "SYN_HOTKEY_SEQUENCE=$SEQUENCE can only be used with trigger=repeat." >&2
      exit 2
    fi
    ;;
  *)
    echo "SYN_HOTKEY_SEQUENCE must be suffix-r, medium-suffix-r, slow-suffix-r, held-r, fast-held-r, long-held-r, or repeat." >&2
    exit 2
    ;;
esac

case "$MODE" in
  selectedWindow)
    /usr/bin/swift script/selection_fixture_window.swift >/tmp/syn-live-hotkey-recording-window.log 2>&1 &
    FIXTURE_WINDOW_PID=$!
    sleep 1
    ;;
  region|smartRegion|screen|allScreens|activeWindowFollow)
    ;;
  *)
    echo "usage: $0 [picker|repeat] [selectedWindow|region|smartRegion|screen|allScreens|activeWindowFollow] [duration-seconds] [--process]" >&2
    exit 2
    ;;
esac

if [[ "$PROCESS_PACKET" == "--process" ]]; then
  EXTRA_APP_ARGS+=(--syn-hotkey-recording-process)
elif [[ -n "$PROCESS_PACKET" ]]; then
  echo "usage: $0 [picker|repeat] [selectedWindow|region|smartRegion|screen|allScreens|activeWindowFollow] [duration-seconds] [--process]" >&2
  exit 2
fi

./script/build_and_run.sh --verify >/tmp/syn-live-hotkey-recording-build.log
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

launch_args=(
  --syn-show-main-window \
  --syn-hotkey-action-log "$ACTION_LOG_PATH" \
  --syn-hotkey-event-log "$EVENT_LOG_PATH" \
  --syn-hotkey-recording-fixture "$TRIGGER" \
  --syn-hotkey-recording-mode "$MODE" \
  --syn-hotkey-recording-log "$LOG_PATH" \
  --syn-hotkey-recording-duration "$DURATION"
)
if [[ ${#EXTRA_APP_ARGS[@]} -gt 0 ]]; then
  launch_args+=("${EXTRA_APP_ARGS[@]}")
fi

/usr/bin/open -n "$STAGED_APP_BUNDLE" --args "${launch_args[@]}"

for _ in {1..50}; do
  if pgrep -x "$APP_NAME" >/dev/null; then
    break
  fi
  sleep 0.2
done

sleep 1
case "$TRIGGER" in
  picker)
    /usr/bin/swift script/post_syn_hotkey_sequence.swift "$SEQUENCE"
    ;;
  repeat)
    /usr/bin/swift script/post_syn_hotkey_sequence.swift "$SEQUENCE"
    ;;
esac

sleep 0.4
SYN_UI_ATTACH_ONLY=1 SYN_UI_WINDOW_TITLE="Syn Recording" ./script/capture_syn_ui.sh "$HUD_CAPTURE_PATH" >/tmp/syn-live-hotkey-recording-hud-capture.log || true

wait_iterations=120
if [[ "$PROCESS_PACKET" == "--process" ]]; then
  wait_iterations=900
fi

for ((attempt = 1; attempt <= wait_iterations; attempt++)); do
  if [[ -s "$LOG_PATH" ]] && grep -q '^status=' "$LOG_PATH"; then
    break
  fi
  sleep 0.2
done

if [[ ! -s "$LOG_PATH" ]] || ! grep -q '^status=' "$LOG_PATH"; then
  SYN_UI_ATTACH_ONLY=1 ./script/capture_syn_ui.sh "$CAPTURE_PATH" >/tmp/syn-live-hotkey-recording-capture.log || true
  echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_RECORDING_TRIGGER=$TRIGGER"
  echo "SYN_LIVE_HOTKEY_RECORDING_MODE=$MODE"
  echo "SYN_LIVE_HOTKEY_RECORDING_REASON=no-status-log"
  echo "SYN_LIVE_HOTKEY_RECORDING_CAPTURE=$CAPTURE_PATH"
  echo "SYN_LIVE_HOTKEY_RECORDING_ACTION_LOG=$ACTION_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_RECORDING_EVENT_LOG=$EVENT_LOG_PATH"
  exit 1
fi

if [[ ! -s "$ACTION_LOG_PATH" ]]; then
  echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_RECORDING_REASON=no-hotkey-action"
  echo "SYN_LIVE_HOTKEY_RECORDING_ACTION_LOG=$ACTION_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_RECORDING_EVENT_LOG=$EVENT_LOG_PATH"
  exit 1
fi

first_action="$(sed -n '1p' "$ACTION_LOG_PATH")"
if [[ "$first_action" != "$TRIGGER" ]]; then
  echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_RECORDING_EXPECTED_ACTION=$TRIGGER"
  echo "SYN_LIVE_HOTKEY_RECORDING_ACTION=$first_action"
  echo "SYN_LIVE_HOTKEY_RECORDING_ACTION_LOG=$ACTION_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_RECORDING_EVENT_LOG=$EVENT_LOG_PATH"
  echo "SYN_LIVE_HOTKEY_RECORDING_CAPTURE=$HUD_CAPTURE_PATH"
  exit 1
fi

status="$(sed -n 's/^status=//p' "$LOG_PATH" | tail -1)"
folder="$(sed -n 's/^folder=//p' "$LOG_PATH" | tail -1)"
raw_recording="$(sed -n 's/^rawRecording=//p' "$LOG_PATH" | tail -1)"
recording="$(sed -n 's/^recording=//p' "$LOG_PATH" | tail -1)"
transcript="$(sed -n 's/^transcript=//p' "$LOG_PATH" | tail -1)"
summary="$(sed -n 's/^summary=//p' "$LOG_PATH" | tail -1)"
zip="$(sed -n 's/^zip=//p' "$LOG_PATH" | tail -1)"
duration="$(sed -n 's/^duration=//p' "$LOG_PATH" | tail -1)"
segments="$(sed -n 's/^segments=//p' "$LOG_PATH" | tail -1)"

expected_status="partial"
if [[ "$PROCESS_PACKET" == "--process" ]]; then
  expected_status="succeeded"
fi

if [[ "$status" != "$expected_status" ]]; then
  echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_RECORDING_EXPECTED_STATUS=$expected_status"
  echo "SYN_LIVE_HOTKEY_RECORDING_STATUS=$status"
  echo "SYN_LIVE_HOTKEY_RECORDING_LOG=$LOG_PATH"
  exit 1
fi

if [[ ! -s "$raw_recording" || ! -s "$folder/raw/capture-session.json" ]]; then
  echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
  echo "SYN_LIVE_HOTKEY_RECORDING_REASON=missing-raw-artifact"
  echo "SYN_LIVE_HOTKEY_RECORDING_RAW=$raw_recording"
  echo "SYN_LIVE_HOTKEY_RECORDING_FOLDER=$folder"
  echo "SYN_LIVE_HOTKEY_RECORDING_LOG=$LOG_PATH"
  exit 1
fi

if [[ "$PROCESS_PACKET" == "--process" ]]; then
  for artifact in "$recording" "$transcript" "$summary" "$zip" "$folder/manifest.json" "$folder/agent-prompt.md" "$folder/frames/candidates/metadata.json"; do
    if [[ ! -s "$artifact" ]]; then
      echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=failed"
      echo "SYN_LIVE_HOTKEY_RECORDING_REASON=missing-processed-artifact"
      echo "SYN_LIVE_HOTKEY_RECORDING_ARTIFACT=$artifact"
      echo "SYN_LIVE_HOTKEY_RECORDING_LOG=$LOG_PATH"
      exit 1
    fi
  done
fi

echo "SYN_LIVE_HOTKEY_RECORDING_FIXTURE=passed"
echo "SYN_LIVE_HOTKEY_RECORDING_TRIGGER=$TRIGGER"
echo "SYN_LIVE_HOTKEY_RECORDING_SEQUENCE=$SEQUENCE"
echo "SYN_LIVE_HOTKEY_RECORDING_ACTION=$first_action"
echo "SYN_LIVE_HOTKEY_RECORDING_MODE=$MODE"
echo "SYN_LIVE_HOTKEY_RECORDING_STATUS=$status"
echo "SYN_LIVE_HOTKEY_RECORDING_PROCESSED=$([[ "$PROCESS_PACKET" == "--process" ]] && echo yes || echo no)"
echo "SYN_LIVE_HOTKEY_RECORDING_DURATION=$duration"
echo "SYN_LIVE_HOTKEY_RECORDING_SEGMENTS=$segments"
echo "SYN_LIVE_HOTKEY_RECORDING_FOLDER=$folder"
echo "SYN_LIVE_HOTKEY_RECORDING_RAW=$raw_recording"
if [[ "$PROCESS_PACKET" == "--process" ]]; then
  echo "SYN_LIVE_HOTKEY_RECORDING_RECORDING=$recording"
  echo "SYN_LIVE_HOTKEY_RECORDING_TRANSCRIPT=$transcript"
  echo "SYN_LIVE_HOTKEY_RECORDING_SUMMARY=$summary"
  echo "SYN_LIVE_HOTKEY_RECORDING_ZIP=$zip"
fi
echo "SYN_LIVE_HOTKEY_RECORDING_LOG=$LOG_PATH"
echo "SYN_LIVE_HOTKEY_RECORDING_ACTION_LOG=$ACTION_LOG_PATH"
echo "SYN_LIVE_HOTKEY_RECORDING_EVENT_LOG=$EVENT_LOG_PATH"
echo "SYN_LIVE_HOTKEY_RECORDING_HUD_CAPTURE=$HUD_CAPTURE_PATH"
