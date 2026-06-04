#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/Syn.app}"
STAGED_APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/Syn"
FIXTURE_ROOT="$ROOT_DIR/build/live-capture-fixtures"
CAFFEINATE_PID=""

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 2
  fi
}

cd "$ROOT_DIR"
require_tool ffprobe

cleanup() {
  if [[ -n "$CAFFEINATE_PID" ]]; then
    kill "$CAFFEINATE_PID" >/dev/null 2>&1 || true
    wait "$CAFFEINATE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

/usr/bin/caffeinate -dimsu -w "$$" >/dev/null 2>&1 &
CAFFEINATE_PID=$!

./script/build_and_run.sh --verify >/tmp/syn-live-fixture-build.log
pkill -x Syn >/dev/null 2>&1 || true
sleep 0.3

if [[ ! -x "$STAGED_APP_BINARY" ]]; then
  echo "Syn staged app binary was not found at $STAGED_APP_BINARY" >&2
  exit 1
fi

mkdir -p "$FIXTURE_ROOT"

LOG_PATH="$FIXTURE_ROOT/live-capture-$(date +%s)-$(/usr/bin/uuidgen).log"
set +e
"$STAGED_APP_BINARY" --syn-live-capture-fixture "$@" --output-root "$FIXTURE_ROOT" 2>&1 | tee "$LOG_PATH"
APP_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$APP_STATUS" -ne 0 ]]; then
  echo "SYN_LIVE_FIXTURE_VERIFICATION=failed"
  echo "SYN_LIVE_FIXTURE_REASON=app-command-failed"
  echo "SYN_LIVE_FIXTURE_LOG=$LOG_PATH"
  exit "$APP_STATUS"
fi

PACKET_DIR="$(awk -F= '/^SYN_LIVE_FIXTURE_PACKET=/{print $2}' "$LOG_PATH" | tail -n 1)"
STATUS="$(awk -F= '/^SYN_LIVE_FIXTURE_STATUS=/{print $2}' "$LOG_PATH" | tail -n 1)"
MODE="$(awk -F= '/^SYN_LIVE_FIXTURE_MODE=/{print $2}' "$LOG_PATH" | tail -n 1)"
PROCESSED="$(awk -F= '/^SYN_LIVE_FIXTURE_PROCESSED=/{print $2}' "$LOG_PATH" | tail -n 1)"

if [[ -z "$PACKET_DIR" || ! -d "$PACKET_DIR" ]]; then
  echo "SYN_LIVE_FIXTURE_VERIFICATION=failed"
  echo "SYN_LIVE_FIXTURE_REASON=missing-packet-dir"
  echo "SYN_LIVE_FIXTURE_PACKET=$PACKET_DIR"
  echo "SYN_LIVE_FIXTURE_LOG=$LOG_PATH"
  exit 1
fi

PACKET_DIR="$PACKET_DIR" STATUS="$STATUS" MODE="$MODE" PROCESSED="$PROCESSED" python3 - <<'PY'
import json
import os
import pathlib
import sys

packet = pathlib.Path(os.environ["PACKET_DIR"])
status = os.environ["STATUS"]
mode = os.environ["MODE"]
processed = os.environ["PROCESSED"] == "true"
errors = []

def require_file(relative: str):
    path = packet / relative
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing or empty {relative}")
    return path

raw_recording = require_file("raw/recording-source.mp4")
capture_session_path = require_file("raw/capture-session.json")
require_file("raw/pointer-events.json")
require_file("raw/active-window-samples.json")
require_file("summary.md")
require_file("agent-prompt.md")

if processed:
    if status != "succeeded":
        errors.append(f"processed live fixture should succeed, got {status}")
    for relative in (
        "recording.mp4",
        "transcript.md",
        "manifest.json",
        "frames/candidates/metadata.json",
    ):
        require_file(relative)
else:
    if status != "partial":
        errors.append(f"raw live fixture should be partial, got {status}")

try:
    session = json.loads(capture_session_path.read_text())
    capture = session.get("capture") or {}
    if capture.get("mode") != mode:
        errors.append(f"capture-session mode {capture.get('mode')} did not match fixture mode {mode}")
    output_size = capture.get("outputSize") or {}
    if output_size and (output_size.get("width", 0) <= 0 or output_size.get("height", 0) <= 0):
        errors.append(f"capture-session output size is invalid: {output_size}")
    if mode == "chromeTab":
        chrome_tab = capture.get("chromeTab") or {}
        if capture.get("appName") != "Google Chrome":
            errors.append(f"chromeTab capture app name is wrong: {capture.get('appName')}")
        if not capture.get("windowID"):
            errors.append("chromeTab capture did not resolve a Chrome windowID")
        if not chrome_tab.get("url"):
            errors.append("chromeTab metadata is missing url")
        if int(chrome_tab.get("windowIndex") or 0) <= 0:
            errors.append("chromeTab metadata is missing windowIndex")
        if int(chrome_tab.get("tabIndex") or 0) <= 0:
            errors.append("chromeTab metadata is missing tabIndex")
        if not chrome_tab.get("windowID"):
            errors.append("chromeTab metadata is missing windowID")
        if not any("Chrome tab URL:" in note for note in capture.get("notes") or []):
            errors.append("chromeTab capture notes are missing the URL note")
except Exception as error:
    errors.append(f"could not parse capture-session.json: {error}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

ffprobe_json="$(mktemp /tmp/syn-live-ffprobe.XXXXXX)"
ffprobe -v error \
  -show_entries stream=codec_type,codec_name,width,height,sample_rate,channels \
  -of json \
  "$PACKET_DIR/raw/recording-source.mp4" > "$ffprobe_json"

python3 - "$ffprobe_json" "$PACKET_DIR" <<'PY'
import json
import pathlib
import sys

probe = pathlib.Path(sys.argv[1])
packet = pathlib.Path(sys.argv[2])
data = json.loads(probe.read_text())
streams = data.get("streams", [])
video = next((stream for stream in streams if stream.get("codec_type") == "video"), None)
audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), None)
errors = []
video_width = 0
video_height = 0

if video is None:
    errors.append("raw recording is missing a video stream")
else:
    if video.get("codec_name") != "h264":
        errors.append(f"raw recording video codec is not h264: {video.get('codec_name')}")
    video_width = int(video.get("width") or 0)
    video_height = int(video.get("height") or 0)
    if video_width <= 0 or video_height <= 0:
        errors.append(f"raw recording video dimensions are invalid: {video.get('width')}x{video.get('height')}")

if audio is None:
    errors.append("raw recording is missing an audio stream")
else:
    if audio.get("codec_name") != "aac":
        errors.append(f"raw recording audio codec is not aac: {audio.get('codec_name')}")
    if int(audio.get("sample_rate") or 0) <= 0:
        errors.append(f"raw recording audio sample rate is invalid: {audio.get('sample_rate')}")
    if int(audio.get("channels") or 0) <= 0:
        errors.append(f"raw recording audio channel count is invalid: {audio.get('channels')}")

try:
    capture = json.loads((packet / "raw/capture-session.json").read_text()).get("capture") or {}
    output_size = capture.get("outputSize") or {}
    if capture.get("mode") == "allScreens" and output_size:
        expected_width = int(output_size.get("width") or 0)
        expected_height = int(output_size.get("height") or 0)
        if (video_width, video_height) != (expected_width, expected_height):
            errors.append(
                "all-screens raw video dimensions do not match capture metadata: "
                f"video={video_width}x{video_height} metadata={expected_width}x{expected_height}"
            )
except Exception as error:
    errors.append(f"could not verify capture-session output size: {error}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY
rm -f "$ffprobe_json"

echo "SYN_LIVE_FIXTURE_VERIFICATION=passed"
echo "SYN_LIVE_FIXTURE_LOG=$LOG_PATH"
