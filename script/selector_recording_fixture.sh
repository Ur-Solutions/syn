#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
MODE="${1:-region}"
DURATION="${2:-1.25}"
PROCESS_PACKET="${3:-}"
WORK_DIR="$ROOT_DIR/build/selector-recording-fixture"
LOG_PATH="$WORK_DIR/$MODE-recording.log"
CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-selector-recording-$MODE-failure.png"
FIXTURE_WINDOW_PID=""
CAFFEINATE_PID=""
EXTRA_APP_ARGS=()

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 2
  fi
}

cd "$ROOT_DIR"
require_tool ffprobe
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/ui-captures"
rm -f "$LOG_PATH"

verify_mp4_media_contract() {
  local video_path="$1"
  local label="$2"
  local require_30fps="${3:-yes}"
  local probe_json
  probe_json="$(mktemp /tmp/syn-selector-ffprobe.XXXXXX)"

  ffprobe -v error \
    -show_entries stream=codec_type,codec_name,avg_frame_rate,r_frame_rate,width,height,sample_rate,channels \
    -of json \
    "$video_path" > "$probe_json"

  python3 - "$probe_json" "$label" "$require_30fps" <<'PY'
import json
import pathlib
import sys
from fractions import Fraction

probe = pathlib.Path(sys.argv[1])
label = sys.argv[2]
require_30fps = sys.argv[3] == "yes"
data = json.loads(probe.read_text())
streams = data.get("streams", [])
video = next((stream for stream in streams if stream.get("codec_type") == "video"), None)
audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), None)
errors = []

def parse_rate(value):
    if not value or value == "0/0":
        return None
    try:
        return float(Fraction(value))
    except Exception:
        return None

if video is None:
    errors.append(f"{label} is missing a video stream")
else:
    if video.get("codec_name") != "h264":
        errors.append(f"{label} video codec is not h264: {video.get('codec_name')}")
    if int(video.get("width") or 0) <= 0 or int(video.get("height") or 0) <= 0:
        errors.append(f"{label} video dimensions are invalid: {video.get('width')}x{video.get('height')}")
    fps_values = [
        rate for rate in (
            parse_rate(video.get("avg_frame_rate")),
            parse_rate(video.get("r_frame_rate")),
        )
        if rate is not None
    ]
    if require_30fps and (not fps_values or not any(abs(rate - 30.0) <= 0.05 for rate in fps_values)):
        errors.append(
            f"{label} video frame rate is not 30 fps: "
            f"avg={video.get('avg_frame_rate')} r={video.get('r_frame_rate')}"
        )

if audio is None:
    errors.append(f"{label} is missing an audio stream")
else:
    if audio.get("codec_name") != "aac":
        errors.append(f"{label} audio codec is not aac: {audio.get('codec_name')}")
    if int(audio.get("sample_rate") or 0) <= 0:
        errors.append(f"{label} audio sample rate is invalid: {audio.get('sample_rate')}")
    if int(audio.get("channels") or 0) <= 0:
        errors.append(f"{label} audio channel count is invalid: {audio.get('channels')}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY
  rm -f "$probe_json"
}

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

case "$MODE" in
  region)
    if [[ "$PROCESS_PACKET" == "--process" ]]; then
      /usr/bin/swift script/selection_fixture_window.swift >/tmp/syn-selector-recording-window.log 2>&1 &
      FIXTURE_WINDOW_PID=$!
      sleep 1
      EXTRA_APP_ARGS+=(--syn-selector-recording-process)
    elif [[ -n "$PROCESS_PACKET" ]]; then
      echo "usage: $0 [region|selectedWindow] [duration-seconds] [--process]" >&2
      exit 2
    fi
    ;;
  selectedWindow|window)
    MODE="selectedWindow"
    LOG_PATH="$WORK_DIR/$MODE-recording.log"
    CAPTURE_PATH="$ROOT_DIR/build/ui-captures/syn-selector-recording-$MODE-failure.png"
    /usr/bin/swift script/selection_fixture_window.swift >/tmp/syn-selector-recording-window.log 2>&1 &
    FIXTURE_WINDOW_PID=$!
    sleep 1
    if [[ "$PROCESS_PACKET" == "--process" ]]; then
      EXTRA_APP_ARGS+=(--syn-selector-recording-process)
    elif [[ -n "$PROCESS_PACKET" ]]; then
      echo "usage: $0 [region|selectedWindow] [duration-seconds] [--process]" >&2
      exit 2
    fi
    ;;
  *)
    echo "usage: $0 [region|selectedWindow] [duration-seconds] [--process]" >&2
    exit 2
    ;;
esac

./script/build_and_run.sh --verify >/tmp/syn-selector-recording-build.log
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

if [[ ! -d "$STAGED_APP_BUNDLE" ]]; then
  echo "Syn staged app bundle was not found at $STAGED_APP_BUNDLE" >&2
  exit 1
fi

launch_args=(
  --syn-selector-recording-fixture "$MODE" \
  --syn-selector-recording-log "$LOG_PATH" \
  --syn-selector-recording-duration "$DURATION"
)
if [[ ${#EXTRA_APP_ARGS[@]} -gt 0 ]]; then
  launch_args+=("${EXTRA_APP_ARGS[@]}")
fi

/usr/bin/open -n "$STAGED_APP_BUNDLE" --args "${launch_args[@]}"

wait_iterations=90
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
  SYN_UI_ATTACH_ONLY=1 ./script/capture_syn_ui.sh "$CAPTURE_PATH" >/tmp/syn-selector-recording-capture.log || true
  echo "SYN_SELECTOR_RECORDING_FIXTURE=failed"
  echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
  echo "SYN_SELECTOR_RECORDING_REASON=no-status-log"
  echo "SYN_SELECTOR_RECORDING_CAPTURE=$CAPTURE_PATH"
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
  echo "SYN_SELECTOR_RECORDING_FIXTURE=failed"
  echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
  echo "SYN_SELECTOR_RECORDING_EXPECTED_STATUS=$expected_status"
  echo "SYN_SELECTOR_RECORDING_STATUS=$status"
  echo "SYN_SELECTOR_RECORDING_LOG=$LOG_PATH"
  exit 1
fi

if [[ ! -f "$raw_recording" ]]; then
  echo "SYN_SELECTOR_RECORDING_FIXTURE=failed"
  echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
  echo "SYN_SELECTOR_RECORDING_REASON=missing-raw-recording"
  echo "SYN_SELECTOR_RECORDING_RAW=$raw_recording"
  echo "SYN_SELECTOR_RECORDING_LOG=$LOG_PATH"
  exit 1
fi

if [[ ! -f "$folder/raw/capture-session.json" ]]; then
  echo "SYN_SELECTOR_RECORDING_FIXTURE=failed"
  echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
  echo "SYN_SELECTOR_RECORDING_REASON=missing-capture-session"
  echo "SYN_SELECTOR_RECORDING_FOLDER=$folder"
  echo "SYN_SELECTOR_RECORDING_LOG=$LOG_PATH"
  exit 1
fi

verify_mp4_media_contract "$raw_recording" "selector raw recording" no

PACKET_DIR="$folder" MODE="$MODE" python3 - <<'PY'
import json
import os
import pathlib
import sys

packet = pathlib.Path(os.environ["PACKET_DIR"])
mode = os.environ["MODE"]
errors = []

for relative in ("raw/capture-session.json", "raw/pointer-events.json", "raw/active-window-samples.json"):
    path = packet / relative
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing or empty {relative}")

try:
    session = json.loads((packet / "raw/capture-session.json").read_text())
    capture = session.get("capture") or {}
    if capture.get("mode") != mode:
        errors.append(f"capture-session mode {capture.get('mode')} did not match fixture mode {mode}")
    output_size = capture.get("outputSize") or {}
    if output_size and (output_size.get("width", 0) <= 0 or output_size.get("height", 0) <= 0):
        errors.append(f"capture-session output size is invalid: {output_size}")
except Exception as error:
    errors.append(f"could not parse capture-session.json: {error}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

if [[ "$PROCESS_PACKET" == "--process" ]]; then
  for artifact in "$recording" "$transcript" "$summary" "$zip" "$folder/manifest.json" "$folder/agent-prompt.md" "$folder/frames/candidates/metadata.json"; do
    if [[ ! -s "$artifact" ]]; then
      echo "SYN_SELECTOR_RECORDING_FIXTURE=failed"
      echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
      echo "SYN_SELECTOR_RECORDING_REASON=missing-processed-artifact"
      echo "SYN_SELECTOR_RECORDING_ARTIFACT=$artifact"
      echo "SYN_SELECTOR_RECORDING_LOG=$LOG_PATH"
      exit 1
    fi
  done

  verify_mp4_media_contract "$recording" "selector processed recording.mp4"

  PACKET_DIR="$folder" ZIP_PATH="$zip" MODE="$MODE" python3 - <<'PY'
import json
import os
import pathlib
import sys
import zipfile

packet = pathlib.Path(os.environ["PACKET_DIR"])
zip_path = pathlib.Path(os.environ["ZIP_PATH"])
mode = os.environ["MODE"]
errors = []

manifest = json.loads((packet / "manifest.json").read_text())
metadata = json.loads((packet / "frames/candidates/metadata.json").read_text())

if manifest.get("capture", {}).get("mode") != mode:
    errors.append(f"manifest capture mode did not match fixture mode: {manifest.get('capture', {}).get('mode')} != {mode}")

processing = manifest.get("processing", {})
expected = {
    "status": "succeeded",
    "transcriptionProvider": "local-whisper.cpp-bundled",
    "transcriptionModel": "ggml-base.en.bin",
    "frameSelectionProvider": "openai-semantic",
    "frameSelectionModel": "gpt-5-mini",
    "summaryProvider": "anthropic",
    "summaryModel": "claude-opus-4-8",
}
for key, value in expected.items():
    if processing.get(key) != value:
        errors.append(f"processing.{key} was {processing.get(key)!r}, expected {value!r}")

if manifest.get("files", {}).get("rawRecording") != "raw/recording-source.mp4":
    errors.append("manifest raw recording path is wrong")
if manifest.get("files", {}).get("rawCaptureSession") != "raw/capture-session.json":
    errors.append("manifest raw capture session path is wrong")
if manifest.get("files", {}).get("pointerEvents") != "raw/pointer-events.json":
    errors.append("manifest pointer events path is wrong")
if manifest.get("files", {}).get("zip") != str(zip_path):
    errors.append("manifest zip path is wrong")

selected = [frame for frame in metadata if frame.get("selected")]
if not metadata:
    errors.append("candidate frame metadata is empty")
if not selected:
    errors.append("no selected frames recorded")
for frame in selected:
    for key in ("fullPath", "compressedPath"):
        value = frame.get(key)
        if not value or not (packet / value).is_file():
            errors.append(f"selected frame missing {key}: {value}")

if not zip_path.is_file() or zip_path.stat().st_size == 0:
    errors.append("packet zip is missing")
else:
    root = packet.name
    names = set(zipfile.ZipFile(zip_path).namelist())
    for relative in ("recording.mp4", "transcript.md", "summary.md", "agent-prompt.md", "manifest.json"):
        if f"{root}/{relative}" not in names:
            errors.append(f"zip missing {relative}")
    if f"{root}/frames/candidates/metadata.json" not in names:
        errors.append("zip missing candidate metadata")
    for frame in selected:
        for key in ("fullPath", "compressedPath"):
            value = frame.get(key)
            if value and f"{root}/{value}" not in names:
                errors.append(f"zip missing selected frame {value}")
    if any(name.startswith(f"{root}/raw/") for name in names):
        errors.append("default zip includes raw sources")

prompt = (packet / "agent-prompt.md").read_text()
for needle in ("Packet folder", "Shareable zip", "## Selected Frame References", "## Summary", "## Transcript Excerpt"):
    if needle not in prompt:
        errors.append(f"agent prompt missing {needle}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY
fi

echo "SYN_SELECTOR_RECORDING_FIXTURE=passed"
echo "SYN_SELECTOR_RECORDING_MODE=$MODE"
echo "SYN_SELECTOR_RECORDING_STATUS=$status"
echo "SYN_SELECTOR_RECORDING_PROCESSED=$([[ "$PROCESS_PACKET" == "--process" ]] && echo yes || echo no)"
echo "SYN_SELECTOR_RECORDING_DURATION=$duration"
echo "SYN_SELECTOR_RECORDING_SEGMENTS=$segments"
echo "SYN_SELECTOR_RECORDING_FOLDER=$folder"
echo "SYN_SELECTOR_RECORDING_RAW=$raw_recording"
if [[ "$PROCESS_PACKET" == "--process" ]]; then
  echo "SYN_SELECTOR_RECORDING_RECORDING=$recording"
  echo "SYN_SELECTOR_RECORDING_TRANSCRIPT=$transcript"
  echo "SYN_SELECTOR_RECORDING_SUMMARY=$summary"
  echo "SYN_SELECTOR_RECORDING_ZIP=$zip"
fi
echo "SYN_SELECTOR_RECORDING_LOG=$LOG_PATH"
