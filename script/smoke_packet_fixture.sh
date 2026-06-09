#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Syn.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Syn"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/Syn.app}"
STAGED_APP_BINARY="$STAGED_APP_BUNDLE/Contents/MacOS/Syn"
FIXTURE_ROOT="$ROOT_DIR/build/fixture-packets"
ENABLE_DEBUG_DYLIB="${SYN_ENABLE_DEBUG_DYLIB:-NO}"
SIGN_IDENTITY="${SYN_CODE_SIGN_IDENTITY:-}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required tool: $1" >&2
    exit 2
  fi
}

require_tool ffmpeg
require_tool ffprobe
require_tool say
require_tool afconvert

source "$ROOT_DIR/script/signing_identity.sh"

cd "$ROOT_DIR"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(find_default_sign_identity || true)"
fi

xcodebuild_args=(
  -project Syn.xcodeproj
  -scheme Syn
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  build
  "ENABLE_DEBUG_DYLIB=$ENABLE_DEBUG_DYLIB"
)

if [[ -n "$SIGN_IDENTITY" ]]; then
  xcodebuild_args+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY")
fi

xcodebuild "${xcodebuild_args[@]}" >/tmp/syn-fixture-xcodebuild.log

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Syn app binary was not built at $APP_BINARY" >&2
  exit 1
fi

mkdir -p "$(dirname "$STAGED_APP_BUNDLE")"
if [[ -d "$STAGED_APP_BUNDLE" ]]; then
  /usr/bin/rsync -aE --delete "$APP_BUNDLE/" "$STAGED_APP_BUNDLE/"
else
  /usr/bin/ditto "$APP_BUNDLE" "$STAGED_APP_BUNDLE"
fi

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f "$STAGED_APP_BUNDLE" >/dev/null 2>&1 || true
fi

WORK_DIR="$(mktemp -d /tmp/syn-packet-fixture.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

NARRATION_AIFF="$WORK_DIR/narration.aiff"
FIXTURE_MP4="$WORK_DIR/fixture.mp4"
PAUSE_SEGMENT_A="$WORK_DIR/pause-segment-a.mp4"
PAUSE_SEGMENT_B="$WORK_DIR/pause-segment-b.mp4"

verify_mp4_media_contract() {
  local video_path="$1"
  local label="$2"
  local probe_json
  probe_json="$(mktemp "$WORK_DIR/ffprobe.XXXXXX")"

  ffprobe -v error \
    -show_entries stream=codec_type,codec_name,avg_frame_rate,r_frame_rate,width,height,sample_rate,channels \
    -of json \
    "$video_path" > "$probe_json"

  python3 - "$probe_json" "$label" <<'PY'
import json
import pathlib
import sys
from fractions import Fraction

probe = pathlib.Path(sys.argv[1])
label = sys.argv[2]
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
    if not fps_values or not any(abs(rate - 30.0) <= 0.05 for rate in fps_values):
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
}

say -o "$NARRATION_AIFF" \
  "Syn fixture packet verification. This recording describes a changing screen, a clicked button, and a final feedback packet."

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=7" \
  -i "$NARRATION_AIFF" \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  -shortest \
  "$FIXTURE_MP4"

ffmpeg -hide_banner -loglevel error -y \
  -i "$FIXTURE_MP4" \
  -t 3 \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  "$PAUSE_SEGMENT_A"

ffmpeg -hide_banner -loglevel error -y \
  -ss 4 \
  -i "$FIXTURE_MP4" \
  -t 3 \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -c:a aac \
  "$PAUSE_SEGMENT_B"

mkdir -p "$FIXTURE_ROOT"

DURATION_WARNING_LOG="$WORK_DIR/duration-warning.log"
"$APP_BINARY" --syn-duration-warning-fixture 2>&1 | tee "$DURATION_WARNING_LOG"
if ! grep -q '^SYN_DURATION_WARNING_FIXTURE=passed$' "$DURATION_WARNING_LOG"; then
  echo "duration warning fixture failed" >&2
  exit 1
fi

SUMMARY_CONTRACT_LOG="$WORK_DIR/summary-contract.log"
"$APP_BINARY" --syn-summary-contract-fixture 2>&1 | tee "$SUMMARY_CONTRACT_LOG"
if ! grep -q '^SYN_SUMMARY_CONTRACT_FIXTURE=passed$' "$SUMMARY_CONTRACT_LOG"; then
  echo "summary contract fixture failed" >&2
  exit 1
fi

ACTIVE_WINDOW_TRACKER_LOG="$WORK_DIR/active-window-tracker.log"
"$APP_BINARY" --syn-active-window-tracker-fixture 2>&1 | tee "$ACTIVE_WINDOW_TRACKER_LOG"
if ! grep -q '^SYN_ACTIVE_WINDOW_TRACKER_FIXTURE=passed$' "$ACTIVE_WINDOW_TRACKER_LOG"; then
  echo "active-window tracker fixture failed" >&2
  exit 1
fi

REPEAT_POLICY_LOG="$WORK_DIR/repeat-policy.log"
"$APP_BINARY" --syn-repeat-policy-fixture 2>&1 | tee "$REPEAT_POLICY_LOG"
if ! grep -q '^SYN_REPEAT_POLICY_FIXTURE=passed$' "$REPEAT_POLICY_LOG"; then
  echo "repeat policy fixture failed" >&2
  exit 1
fi

PACKET_LAYOUT_LOG="$WORK_DIR/packet-layout.log"
"$APP_BINARY" --syn-packet-layout-fixture 2>&1 | tee "$PACKET_LAYOUT_LOG"
if ! grep -q '^SYN_PACKET_LAYOUT_FIXTURE=passed$' "$PACKET_LAYOUT_LOG"; then
  echo "packet layout fixture failed" >&2
  exit 1
fi

SECRET_STORE_LOG="$WORK_DIR/secret-store.log"
"$APP_BINARY" --syn-secret-store-fixture 2>&1 | tee "$SECRET_STORE_LOG"
if ! grep -q '^SYN_SECRET_STORE_FIXTURE=passed$' "$SECRET_STORE_LOG"; then
  echo "secret store fixture failed" >&2
  exit 1
fi

PERMISSION_STATUS_LOG="$WORK_DIR/permission-status.log"
"$APP_BINARY" --syn-permission-status-fixture 2>&1 | tee "$PERMISSION_STATUS_LOG"
if ! grep -q '^SYN_PERMISSION_BUNDLE_ID=com.trmd.syn$' "$PERMISSION_STATUS_LOG"; then
  echo "permission status fixture did not report the Syn bundle id" >&2
  exit 1
fi
if ! grep -q '^SYN_PERMISSION_MICROPHONE=' "$PERMISSION_STATUS_LOG"; then
  echo "permission status fixture did not report microphone status" >&2
  exit 1
fi
if ! grep -q '^SYN_PERMISSION_MICROPHONE_RECORD=' "$PERMISSION_STATUS_LOG"; then
  echo "permission status fixture did not report record permission status" >&2
  exit 1
fi
if ! grep -q '^SYN_PERMISSION_MICROPHONE_CAPTURE_DEVICE=' "$PERMISSION_STATUS_LOG"; then
  echo "permission status fixture did not report capture-device permission status" >&2
  exit 1
fi

CAPTURE_CONFIGURATION_LOG="$WORK_DIR/capture-configuration.log"
"/usr/bin/caffeinate" -u -t 10 >/dev/null 2>&1 &
CAFFEINATE_PID=$!
sleep 1
set +e
"$STAGED_APP_BINARY" --syn-capture-configuration-fixture 2>&1 | tee "$CAPTURE_CONFIGURATION_LOG"
CAPTURE_CONFIGURATION_STATUS=${PIPESTATUS[0]}
set -e
kill "$CAFFEINATE_PID" >/dev/null 2>&1 || true
wait "$CAFFEINATE_PID" >/dev/null 2>&1 || true
if [[ "$CAPTURE_CONFIGURATION_STATUS" -ne 0 ]]; then
  echo "capture configuration fixture failed to run" >&2
  exit 1
fi
if ! grep -q '^SYN_CAPTURE_CONFIGURATION_FIXTURE=passed$' "$CAPTURE_CONFIGURATION_LOG"; then
  echo "capture configuration fixture failed" >&2
  exit 1
fi

HISTORY_ACTIONS_LOG="$WORK_DIR/history-actions.log"
SYN_HISTORY_STORE_PATH="$WORK_DIR/history-actions.json" "$APP_BINARY" --syn-history-actions-fixture 2>&1 | tee "$HISTORY_ACTIONS_LOG"
if ! grep -q '^SYN_HISTORY_ACTIONS_FIXTURE=passed$' "$HISTORY_ACTIONS_LOG"; then
  echo "history actions fixture failed" >&2
  exit 1
fi

HOTKEY_LOG="$WORK_DIR/hotkey.log"
pkill -x Syn >/dev/null 2>&1 || true
sleep 0.3
"$STAGED_APP_BINARY" --syn-hotkey-fixture 2>&1 | tee "$HOTKEY_LOG"
if ! grep -q '^SYN_HOTKEY_FIXTURE=passed$' "$HOTKEY_LOG"; then
  echo "hotkey fixture failed" >&2
  exit 1
fi

CAPTURE_PICKER_CONTRACT_LOG="$WORK_DIR/capture-picker-contract.log"
"$APP_BINARY" --syn-capture-picker-contract-fixture 2>&1 | tee "$CAPTURE_PICKER_CONTRACT_LOG"
if ! grep -q '^SYN_CAPTURE_PICKER_CONTRACT_FIXTURE=passed$' "$CAPTURE_PICKER_CONTRACT_LOG"; then
  echo "capture picker contract fixture failed" >&2
  exit 1
fi

PROMPT_PROFILE_LOG="$WORK_DIR/prompt-profile.log"
SYN_PREFERENCES_PATH="$WORK_DIR/prompt-profile-preferences.json" "$APP_BINARY" --syn-prompt-profile-fixture 2>&1 | tee "$PROMPT_PROFILE_LOG"
if ! grep -q '^SYN_PROMPT_PROFILE_FIXTURE=passed$' "$PROMPT_PROFILE_LOG"; then
  echo "prompt profile fixture failed" >&2
  exit 1
fi

CHROME_TAB_LOG="$WORK_DIR/chrome-tab.log"
"$APP_BINARY" --syn-chrome-tab-fixture 2>&1 | tee "$CHROME_TAB_LOG"
if ! grep -q '^SYN_CHROME_TAB_FIXTURE=passed$' "$CHROME_TAB_LOG"; then
  echo "chrome-tab fixture failed" >&2
  exit 1
fi

RAW_ZIP_LOG="$WORK_DIR/raw-zip.log"
"$APP_BINARY" --syn-raw-zip-fixture 2>&1 | tee "$RAW_ZIP_LOG"
if ! grep -q '^SYN_RAW_ZIP_FIXTURE=passed$' "$RAW_ZIP_LOG"; then
  echo "raw-zip fixture failed" >&2
  exit 1
fi
if ! grep -q '^SYN_COMPACT_ZIP_INCLUDES_AGENT_FILES=yes$' "$RAW_ZIP_LOG"; then
  echo "compact zip fixture did not include the expected agent-facing files" >&2
  exit 1
fi
if ! grep -q '^SYN_COMPACT_ZIP_EXCLUDES_HEAVY_FILES=yes$' "$RAW_ZIP_LOG"; then
  echo "compact zip fixture did not exclude heavy/raw files" >&2
  exit 1
fi

VIDEO_TRIM_LOG="$WORK_DIR/video-trim.log"
"$APP_BINARY" --syn-video-trim-fixture "$FIXTURE_MP4" 2>&1 | tee "$VIDEO_TRIM_LOG"
if ! grep -q '^SYN_VIDEO_TRIM_FIXTURE=passed$' "$VIDEO_TRIM_LOG"; then
  echo "video-trim fixture failed" >&2
  exit 1
fi
if ! grep -q '^SYN_VIDEO_TRIM_MANIFEST=updated$' "$VIDEO_TRIM_LOG"; then
  echo "video-trim fixture did not update the manifest" >&2
  exit 1
fi

ACTIVE_WINDOW_RENDER_LOG="$WORK_DIR/active-window-render.log"
"$APP_BINARY" --syn-active-window-render-fixture "$FIXTURE_MP4" 2>&1 | tee "$ACTIVE_WINDOW_RENDER_LOG"
if ! grep -q '^SYN_ACTIVE_WINDOW_RENDER_FIXTURE=passed$' "$ACTIVE_WINDOW_RENDER_LOG"; then
  echo "active-window render fixture failed" >&2
  exit 1
fi

SMART_REGION_RENDER_LOG="$WORK_DIR/smart-region-render.log"
"$APP_BINARY" --syn-smart-region-render-fixture "$FIXTURE_MP4" 2>&1 | tee "$SMART_REGION_RENDER_LOG"
if ! grep -q '^SYN_SMART_REGION_RENDER_FIXTURE=passed$' "$SMART_REGION_RENDER_LOG"; then
  echo "smart-region render fixture failed" >&2
  exit 1
fi
if ! grep -q '^SYN_SMART_REGION_RENDER_INTERVALS=2$' "$SMART_REGION_RENDER_LOG"; then
  echo "smart-region render fixture did not produce the expected moving intervals" >&2
  exit 1
fi

ALL_SCREENS_RENDER_LOG="$WORK_DIR/all-screens-render.log"
"$APP_BINARY" --syn-all-screens-render-fixture "$FIXTURE_MP4" 2>&1 | tee "$ALL_SCREENS_RENDER_LOG"
if ! grep -q '^SYN_ALL_SCREENS_RENDER_FIXTURE=passed$' "$ALL_SCREENS_RENDER_LOG"; then
  echo "all-screens render fixture failed" >&2
  exit 1
fi

ANNOTATION_RECORDER_LOG="$WORK_DIR/annotation-recorder.log"
"$APP_BINARY" --syn-annotation-recorder-fixture 2>&1 | tee "$ANNOTATION_RECORDER_LOG"
if ! grep -q '^SYN_ANNOTATION_RECORDER_FIXTURE=passed$' "$ANNOTATION_RECORDER_LOG"; then
  echo "annotation recorder fixture failed" >&2
  exit 1
fi
if ! grep -q '^SYN_ANNOTATION_RECORDER_TOOLS=rectangle,arrow,line,ellipse,text,pen$' "$ANNOTATION_RECORDER_LOG"; then
  echo "annotation recorder fixture did not capture the expected tools" >&2
  exit 1
fi

ANNOTATION_RENDER_LOG="$WORK_DIR/annotation-render.log"
"$APP_BINARY" --syn-annotation-render-fixture "$FIXTURE_MP4" 2>&1 | tee "$ANNOTATION_RENDER_LOG"
if ! grep -q '^SYN_ANNOTATION_RENDER_FIXTURE=passed$' "$ANNOTATION_RENDER_LOG"; then
  echo "annotation render fixture failed" >&2
  exit 1
fi

FRAME_DEBUG_LOG="$WORK_DIR/frame-debug.log"
"$APP_BINARY" --syn-frame-debug-fixture "$FIXTURE_MP4" --output-root "$FIXTURE_ROOT" 2>&1 | tee "$FRAME_DEBUG_LOG"
if ! grep -q '^SYN_FRAME_DEBUG_FIXTURE=passed$' "$FRAME_DEBUG_LOG"; then
  echo "frame debug fixture failed" >&2
  exit 1
fi

OCR_LOG="$WORK_DIR/ocr.log"
"$APP_BINARY" --syn-ocr-fixture --output-root "$FIXTURE_ROOT" 2>&1 | tee "$OCR_LOG"
if ! grep -q '^SYN_OCR_FIXTURE=passed$' "$OCR_LOG"; then
  echo "ocr fixture failed" >&2
  exit 1
fi
if ! grep -q '^SYN_OCR_TEXT=.*SYN.*OCR.*4829' "$OCR_LOG"; then
  echo "ocr fixture did not recognize the expected text" >&2
  exit 1
fi

FIXTURE_LOG="$WORK_DIR/fixture.log"
"$APP_BINARY" --syn-process-fixture "$FIXTURE_MP4" --output-root "$FIXTURE_ROOT" 2>&1 | tee "$FIXTURE_LOG"

PACKET_DIR="$(awk -F= '/^SYN_FIXTURE_PACKET=/{print $2}' "$FIXTURE_LOG" | tail -n 1)"
ZIP_PATH="$(awk -F= '/^SYN_FIXTURE_ZIP=/{print $2}' "$FIXTURE_LOG" | tail -n 1)"

if [[ -z "$PACKET_DIR" || ! -d "$PACKET_DIR" ]]; then
  echo "fixture did not produce a packet directory" >&2
  exit 1
fi

required_paths=(
  "$PACKET_DIR/recording.mp4"
  "$PACKET_DIR/transcript.md"
  "$PACKET_DIR/summary.md"
  "$PACKET_DIR/agent-prompt.md"
  "$PACKET_DIR/agent-prompts/general-coding.md"
  "$PACKET_DIR/agent-prompts/implementation-plan.md"
  "$PACKET_DIR/agent-prompts/qa-bug-report.md"
  "$PACKET_DIR/project-context.md"
  "$PACKET_DIR/semantic-segments.json"
  "$PACKET_DIR/semantic-timeline.md"
  "$PACKET_DIR/manifest.json"
  "$PACKET_DIR/frames/candidates/metadata.json"
  "$PACKET_DIR/raw/recording-source.mp4"
  "$PACKET_DIR/raw/audio-source.wav"
  "$PACKET_DIR/raw/capture-session.json"
  "$PACKET_DIR/raw/pointer-events.json"
  "$PACKET_DIR/raw/annotations.json"
  "$PACKET_DIR/raw/active-window-samples.json"
)

for path in "${required_paths[@]}"; do
  if [[ ! -s "$path" ]]; then
    echo "missing or empty packet artifact: $path" >&2
    exit 1
  fi
done

verify_mp4_media_contract "$PACKET_DIR/recording.mp4" "processed recording.mp4"
verify_mp4_media_contract "$PACKET_DIR/raw/recording-source.mp4" "raw recording-source.mp4"

if [[ -z "$ZIP_PATH" || ! -s "$ZIP_PATH" ]]; then
  echo "missing or empty packet zip: $ZIP_PATH" >&2
  exit 1
fi

zip_listing="$(/usr/bin/zipinfo -1 "$ZIP_PATH")"
if echo "$zip_listing" | grep -q '/raw/'; then
  echo "default packet zip includes raw sources" >&2
  exit 1
fi

zip_root="$(basename "$PACKET_DIR")"
zip_required_paths=(
  "$zip_root/recording.mp4"
  "$zip_root/transcript.md"
  "$zip_root/summary.md"
  "$zip_root/agent-prompt.md"
  "$zip_root/agent-prompts/general-coding.md"
  "$zip_root/agent-prompts/implementation-plan.md"
  "$zip_root/agent-prompts/qa-bug-report.md"
  "$zip_root/project-context.md"
  "$zip_root/semantic-segments.json"
  "$zip_root/semantic-timeline.md"
  "$zip_root/manifest.json"
  "$zip_root/frames/candidates/metadata.json"
)

for path in "${zip_required_paths[@]}"; do
  if ! echo "$zip_listing" | grep -qx "$path"; then
    echo "packet zip is missing required artifact: $path" >&2
    exit 1
  fi
done

python3 - "$PACKET_DIR" "$ZIP_PATH" <<'PY'
import json
import pathlib
import sys
import zipfile

packet = pathlib.Path(sys.argv[1])
zip_path = pathlib.Path(sys.argv[2])

manifest = json.loads((packet / "manifest.json").read_text())
metadata = json.loads((packet / "frames/candidates/metadata.json").read_text())
pointer_events = json.loads((packet / "raw/pointer-events.json").read_text())
annotations = json.loads((packet / "raw/annotations.json").read_text())
semantic_segments = json.loads((packet / "semantic-segments.json").read_text())
zip_names = set(zipfile.ZipFile(zip_path).namelist())
zip_root = packet.name

errors = []
if manifest["files"]["recording"] != "recording.mp4":
    errors.append("manifest recording path is wrong")
if manifest["files"]["rawRecording"] != "raw/recording-source.mp4":
    errors.append("manifest raw recording path is wrong")
if manifest["files"].get("rawCaptureSession") != "raw/capture-session.json":
    errors.append("manifest raw capture session path is wrong")
if manifest["files"]["pointerEvents"] != "raw/pointer-events.json":
    errors.append("manifest pointer-events path is wrong")
if manifest["files"].get("annotations") != "raw/annotations.json":
    errors.append("manifest annotations path is wrong")
if manifest["files"].get("activeWindowSamples") != "raw/active-window-samples.json":
    errors.append("manifest active-window sample path is wrong")
if manifest["files"]["zip"] != str(zip_path):
    errors.append("manifest zip path is wrong")
if manifest["files"].get("agentPrompts") != "agent-prompts":
    errors.append("manifest agent-prompts path is wrong")
if manifest.get("agentPromptProfile") != "generalCoding":
    errors.append(f"manifest agent prompt profile is wrong: {manifest.get('agentPromptProfile')}")
if manifest["files"].get("projectContext") != "project-context.md":
    errors.append(f"manifest project context path is wrong: {manifest['files'].get('projectContext')}")
if manifest["files"].get("semanticSegments") != "semantic-segments.json":
    errors.append(f"manifest semantic segments path is wrong: {manifest['files'].get('semanticSegments')}")
if manifest["files"].get("semanticTimeline") != "semantic-timeline.md":
    errors.append(f"manifest semantic timeline path is wrong: {manifest['files'].get('semanticTimeline')}")
processing = manifest.get("processing", {})
if processing.get("status") != "succeeded":
    errors.append(f"manifest processing status is not succeeded: {processing.get('status')}")
if processing.get("transcriptionProvider") != "local-whisper.cpp-bundled":
    errors.append(f"manifest did not use bundled Whisper: {processing.get('transcriptionProvider')}")
if processing.get("transcriptionModel") != "ggml-base.en.bin":
    errors.append(f"manifest transcription model is wrong: {processing.get('transcriptionModel')}")
if processing.get("frameSelectionProvider") != "openai-semantic":
    errors.append(f"manifest did not use OpenAI semantic frame planning: {processing.get('frameSelectionProvider')}")
if processing.get("frameSelectionModel") != "gpt-5-mini":
    errors.append(f"manifest frame selection model is wrong: {processing.get('frameSelectionModel')}")
if processing.get("summaryProvider") != "anthropic":
    errors.append(f"manifest did not use Anthropic summary: {processing.get('summaryProvider')}")
if processing.get("summaryModel") != "claude-sonnet-4-6":
    errors.append(f"manifest summary model is wrong: {processing.get('summaryModel')}")
stage_timings = processing.get("stageTimings") or []
expected_stage_names = {
    "write-raw-recovery-metadata",
    "merge-raw-segments",
    "render-processed-video",
    "extract-frames-and-ocr",
    "transcribe-local-whisper",
    "plan-semantic-frames-openai",
    "summarize-claude",
    "create-default-zip",
}
stage_names = {stage.get("name") for stage in stage_timings}
missing_stages = expected_stage_names - stage_names
if missing_stages:
    errors.append(f"manifest processing stage timings are missing stages: {sorted(missing_stages)}")
if any(float(stage.get("durationSeconds", -1)) < 0 for stage in stage_timings):
    errors.append("manifest processing stage timing has a negative duration")
if manifest["pointerEventCount"] < 3:
    errors.append("pointer event count is too low")
if not pointer_events or not any(event.get("videoCoordinates") for event in pointer_events):
    errors.append("pointer events were not mapped into video coordinates")
if not any(event.get("kind") == "leftMouseDown" for event in pointer_events):
    errors.append("click metadata was not preserved")
if manifest.get("annotationCount") != 5:
    errors.append(f"manifest annotation count is wrong: {manifest.get('annotationCount')}")
if len(annotations) != 5:
    errors.append(f"raw annotation metadata count is wrong: {len(annotations)}")
if {annotation.get("tool") for annotation in annotations} != {"rectangle", "line", "ellipse", "text", "pen"}:
    errors.append(f"raw annotation tools are wrong: {[annotation.get('tool') for annotation in annotations]}")
if not all(annotation.get("videoPoints") for annotation in annotations):
    errors.append("annotation strokes were not mapped into video coordinates")

annotation_mapping = manifest.get("annotationMapping")
if not annotation_mapping:
    errors.append("manifest is missing annotation mapping metadata")
else:
    if annotation_mapping.get("mappedStrokeCount") != 5:
        errors.append(f"annotation mapping mapped count is wrong: {annotation_mapping.get('mappedStrokeCount')}")
    if annotation_mapping.get("renderedStrokeCount") != 5:
        errors.append(f"annotation mapping rendered count is wrong: {annotation_mapping.get('renderedStrokeCount')}")
    if annotation_mapping.get("videoCoordinateSpace") != "final recording pixels with origin at top-left":
        errors.append("annotation mapping video coordinate space is wrong")

pointer_mapping = manifest.get("pointerMapping")
if not pointer_mapping:
    errors.append("manifest is missing pointer mapping metadata")
else:
    if pointer_mapping.get("mappedEventCount", 0) < 1:
        errors.append("pointer mapping did not count mapped events")
    if pointer_mapping.get("renderedClickCount", 0) < 1:
        errors.append("pointer mapping did not count rendered click overlays")
    if pointer_mapping.get("videoCoordinateSpace") != "final recording pixels with origin at top-left":
        errors.append("pointer mapping video coordinate space is wrong")
    if pointer_mapping.get("usesActiveWindowTimeline") is not False:
        errors.append("screen fixture should store active-window metadata without using active-window timeline rendering")
    render_size = pointer_mapping.get("renderSize") or {}
    if render_size.get("width", 0) <= 0 or render_size.get("height", 0) <= 0:
        errors.append("pointer mapping render size is invalid")

selected = [frame for frame in metadata if frame.get("selected")]
if not selected:
    errors.append("no selected frames in candidate metadata")
if not semantic_segments:
    errors.append("semantic segments are missing")
else:
    previous_end = 0
    for segment in semantic_segments:
        if segment.get("index", 0) <= 0:
            errors.append(f"semantic segment index is invalid: {segment}")
        if segment.get("endTime", 0) < segment.get("startTime", 0):
            errors.append(f"semantic segment has negative duration: {segment}")
        if segment.get("startTime", 0) + 0.001 < previous_end:
            errors.append("semantic segments overlap out of order")
        previous_end = segment.get("endTime", previous_end)
        if not segment.get("title"):
            errors.append("semantic segment is missing title")
        if not segment.get("summary"):
            errors.append("semantic segment is missing summary")
        if not segment.get("source"):
            errors.append("semantic segment is missing source")
    segment_frame_paths = {
        frame_path
        for segment in semantic_segments
        for frame_path in segment.get("framePaths", [])
    }
    selected_frame_paths = {
        path
        for frame in selected
        for path in (frame.get("fullPath"), frame.get("compressedPath"))
        if path
    }
    if selected_frame_paths and not segment_frame_paths.intersection(selected_frame_paths):
        errors.append("semantic segments do not reference selected frame files")
if len(metadata) < 2:
    errors.append("candidate metadata has too few sampled frames")
candidate_files = sorted(path.relative_to(packet).as_posix() for path in (packet / "frames/candidates").iterdir() if path.is_file())
if candidate_files != ["frames/candidates/metadata.json"]:
    errors.append(f"candidate screenshots should not be kept by default; found: {candidate_files}")
full_files = sorted(path.relative_to(packet).as_posix() for path in (packet / "frames/full").glob("*") if path.is_file())
compressed_files = sorted(path.relative_to(packet).as_posix() for path in (packet / "frames/compressed").glob("*") if path.is_file())
selected_full_paths = sorted(frame.get("fullPath") for frame in selected if frame.get("fullPath"))
selected_compressed_paths = sorted(frame.get("compressedPath") for frame in selected if frame.get("compressedPath"))
if full_files != selected_full_paths:
    errors.append("frames/full contents do not exactly match selected frame metadata")
if compressed_files != selected_compressed_paths:
    errors.append("frames/compressed contents do not exactly match selected frame metadata")
for frame in metadata[1:]:
    diff = frame.get("pixelDifferenceFromPrevious")
    if diff is None:
        errors.append("candidate metadata is missing pixel difference from previous sampled frame")
    elif not (0 <= diff <= 1):
        errors.append(f"candidate pixel difference is out of range: {diff}")
if not any(frame.get("appName") == "Syn Fixture" for frame in metadata):
    errors.append("candidate metadata is missing active app name")
if not any(frame.get("windowTitle") in ("Synthetic Packet Verification", "Fixture Topic Shift") for frame in metadata):
    errors.append("candidate metadata is missing active window title")
if not any(frame.get("captureBounds") for frame in metadata):
    errors.append("candidate metadata is missing capture bounds")
for frame in selected:
    for key in ("fullPath", "compressedPath"):
        value = frame.get(key)
        if not value or not (packet / value).is_file():
            errors.append(f"selected frame missing {key}: {value}")
        elif f"{zip_root}/{value}" not in zip_names:
            errors.append(f"default packet zip is missing selected frame {value}")
    full_value = frame.get("fullPath")
    compressed_value = frame.get("compressedPath")
    full_path = packet / full_value if isinstance(full_value, str) else None
    compressed_path = packet / compressed_value if isinstance(compressed_value, str) else None
    if full_path and full_path.is_file():
        if full_path.suffix.lower() != ".png" or full_path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            errors.append(f"full frame is not a PNG: {frame.get('fullPath')}")
        full_size = frame.get("fullSize") or {}
        if full_size.get("width", 0) <= 0 or full_size.get("height", 0) <= 0:
            errors.append(f"selected frame missing full dimensions: {frame.get('fullPath')}")
        if frame.get("fullBytes") != full_path.stat().st_size:
            errors.append(f"selected frame full byte count does not match disk: {frame.get('fullPath')}")
    if compressed_path and compressed_path.is_file():
        compressed_bytes = compressed_path.read_bytes()
        if compressed_path.suffix.lower() != ".jpg" or compressed_bytes[:2] != b"\xff\xd8":
            errors.append(f"compressed frame is not a JPEG: {frame.get('compressedPath')}")
        compressed_size = frame.get("compressedSize") or {}
        if compressed_size.get("width", 0) <= 0 or compressed_size.get("height", 0) <= 0:
            errors.append(f"selected frame missing compressed dimensions: {frame.get('compressedPath')}")
        if max(compressed_size.get("width", 0), compressed_size.get("height", 0)) > 1600:
            errors.append(f"compressed frame exceeds 1600px long edge: {frame.get('compressedPath')}")
        if frame.get("compressedBytes") != compressed_path.stat().st_size:
            errors.append(f"selected frame compressed byte count does not match disk: {frame.get('compressedPath')}")
        if compressed_path.stat().st_size > 3_000_000:
            errors.append(f"compressed frame is too large for the default LLM-ready profile: {frame.get('compressedPath')}")

agent_prompt = (packet / "agent-prompt.md").read_text()
project_context = (packet / "project-context.md").read_text()
semantic_timeline = (packet / "semantic-timeline.md").read_text()
for needle in (
    "# Project Context",
    "Fixture Project",
    "Package.swift",
    "README Excerpt",
    "Syn can attach bounded local project context",
):
    if needle not in project_context:
        errors.append(f"project context is missing expected content: {needle}")
for forbidden in ("SYN_SHOULD_NOT_APPEAR", "node_modules/ignored.txt"):
    if forbidden in project_context:
        errors.append(f"project context leaked excluded fixture content: {forbidden}")
for needle in ("# Semantic Timeline", "Representative frame", "Source:"):
    if needle not in semantic_timeline:
        errors.append(f"semantic timeline is missing expected content: {needle}")
profile_files = {
    "General Coding Agent": packet / "agent-prompts/general-coding.md",
    "Implementation Plan": packet / "agent-prompts/implementation-plan.md",
    "QA Bug Report": packet / "agent-prompts/qa-bug-report.md",
}
for title, path in profile_files.items():
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing prompt profile file: {path.relative_to(packet)}")
        continue
    text = path.read_text()
    if f"# Syn Feedback Packet - {title}" not in text:
        errors.append(f"prompt profile file has wrong title: {path.relative_to(packet)}")
    if "## Prompt Profile" not in text:
        errors.append(f"prompt profile file missing profile section: {path.relative_to(packet)}")
    if f"{zip_root}/agent-prompts/{path.name}" not in zip_names:
        errors.append(f"default packet zip is missing prompt profile file: {path.relative_to(packet)}")
if (packet / "agent-prompts/general-coding.md").read_text() != agent_prompt:
    errors.append("default agent-prompt.md should match the selected General Coding profile")
if "## QA Focus" not in (packet / "agent-prompts/qa-bug-report.md").read_text():
    errors.append("QA prompt profile is missing QA focus section")
if "## Planning Focus" not in (packet / "agent-prompts/implementation-plan.md").read_text():
    errors.append("implementation-plan prompt profile is missing planning focus section")
if "Fixture recording" not in agent_prompt:
    errors.append("agent prompt does not include fixture context")
if str(packet) not in agent_prompt:
    errors.append("agent prompt does not reference the packet folder")
if str(zip_path) not in agent_prompt:
    errors.append("agent prompt does not reference the shareable zip")
if "Packet folder" not in agent_prompt or "Shareable zip" not in agent_prompt:
    errors.append("agent prompt does not label folder and zip paths")
for needle in (
    "## How To Use This Packet",
    "## Prompt Profile",
    "## Packet Files",
    "## Capture And Processing",
    "## Processing Notes",
    "## Processing Timings",
    "## Pointer And Pause Metadata",
    "## Selected Frame References",
    "## Semantic Timeline",
    "## Project Context",
    "## Summary",
    "## Transcript Excerpt",
    "project-context.md",
    "semantic-segments.json",
    "semantic-timeline.md",
    "Fixture Project",
    "raw/annotations.json",
    "local Whisper transcript",
    "processed final recording",
):
    if needle not in agent_prompt:
        errors.append(f"agent prompt is missing enriched handoff content: {needle}")
if manifest["capture"]["mode"] not in agent_prompt:
    errors.append("agent prompt does not include capture mode metadata")
if manifest["processing"]["transcriptionProvider"] not in agent_prompt:
    errors.append("agent prompt does not include transcription provider metadata")
if manifest["processing"]["summaryProvider"] not in agent_prompt:
    errors.append("agent prompt does not include summary provider metadata")
if "Total measured processing time:" not in agent_prompt:
    errors.append("agent prompt does not include processing stage timings")
if "Pointer events:" not in agent_prompt:
    errors.append("agent prompt does not include pointer mapping summary")
if "Annotations:" not in agent_prompt:
    errors.append("agent prompt does not include annotation mapping summary")
if selected and not any(frame.get("fullPath") and frame.get("fullPath") in agent_prompt for frame in selected):
    errors.append("agent prompt does not reference selected full-frame files")
if selected and not any(frame.get("compressedPath") and frame.get("compressedPath") in agent_prompt for frame in selected):
    errors.append("agent prompt does not reference selected compressed-frame files")
if len((packet / "transcript.md").read_text().strip()) < 40:
    errors.append("transcript is unexpectedly short")
if len((packet / "summary.md").read_text().strip()) < 40:
    errors.append("summary is unexpectedly short")
summary_lower = (packet / "summary.md").read_text().lower()
for needle in ("prioritized", "timestamp", "frame", "suggested", "open question"):
    if needle not in summary_lower:
        errors.append(f"summary is missing expected section concept: {needle}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

CLIPBOARD_PROMPT="$WORK_DIR/clipboard-handoff.txt"
/usr/bin/pbpaste > "$CLIPBOARD_PROMPT"
# The auto-copy is a concise, text-only handoff (not the full prompt, not a folder file URL):
# it must reference the packet folder and direct the agent to summary.md + agent-prompt.md.
for needle in "$PACKET_DIR" "summary.md" "agent-prompt.md" "progress.md"; do
  if ! /usr/bin/grep -qF "$needle" "$CLIPBOARD_PROMPT"; then
    echo "clipboard handoff is missing '$needle' after packet processing" >&2
    exit 1
  fi
done

PARTIAL_PACKET_LOG="$WORK_DIR/partial-packet-fixture.log"
"$APP_BINARY" --syn-partial-packet-fixture "$FIXTURE_MP4" --output-root "$FIXTURE_ROOT" 2>&1 | tee "$PARTIAL_PACKET_LOG"

PARTIAL_PACKET_DIR="$(awk -F= '/^SYN_PARTIAL_PACKET_FIXTURE_PACKET=/{print $2}' "$PARTIAL_PACKET_LOG" | tail -n 1)"
PARTIAL_PACKET_ZIP="$(awk -F= '/^SYN_PARTIAL_PACKET_FIXTURE_ZIP=/{print $2}' "$PARTIAL_PACKET_LOG" | tail -n 1)"
PARTIAL_PACKET_STATUS="$(awk -F= '/^SYN_PARTIAL_PACKET_FIXTURE_STATUS=/{print $2}' "$PARTIAL_PACKET_LOG" | tail -n 1)"

if [[ -z "$PARTIAL_PACKET_DIR" || ! -d "$PARTIAL_PACKET_DIR" ]]; then
  echo "partial packet fixture did not produce a packet directory" >&2
  exit 1
fi

if [[ "$PARTIAL_PACKET_STATUS" != "partial" ]]; then
  echo "partial packet fixture did not produce partial status: $PARTIAL_PACKET_STATUS" >&2
  exit 1
fi

PARTIAL_PACKET_DIR="$PARTIAL_PACKET_DIR" PARTIAL_PACKET_ZIP="$PARTIAL_PACKET_ZIP" python3 - <<'PY'
import json
import os
import pathlib
import sys
import zipfile

packet = pathlib.Path(os.environ["PARTIAL_PACKET_DIR"])
zip_path = pathlib.Path(os.environ["PARTIAL_PACKET_ZIP"])
errors = []

for relative in (
    "summary.md",
    "transcript.md",
    "agent-prompt.md",
    "manifest.json",
    "recording.mp4",
    "raw/recording-source.mp4",
    "raw/capture-session.json",
    "raw/pointer-events.json",
):
    path = packet / relative
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"partial packet is missing {relative}")

manifest = json.loads((packet / "manifest.json").read_text())
processing = manifest.get("processing", {})
if processing.get("status") != "partial":
    errors.append(f"partial manifest status is not partial: {processing.get('status')}")
if processing.get("summaryProvider") != "local-partial-fallback":
    errors.append(f"partial summary provider is wrong: {processing.get('summaryProvider')}")
notes = "\n".join(processing.get("notes") or [])
if "Processing failed before Syn could finish the packet" not in notes:
    errors.append("partial manifest does not record the processing failure")
if "Raw capture metadata was retained for retry" not in notes:
    errors.append("partial manifest does not record retry metadata retention")

summary = (packet / "summary.md").read_text()
if "Syn could not finish processing this recording" not in summary:
    errors.append("partial summary does not explain the processing failure")
if "Retry Processing" not in summary:
    errors.append("partial summary does not direct the user to retry")

prompt = (packet / "agent-prompt.md").read_text()
for needle in (
    "Processing status: partial",
    "local-partial-fallback",
    "Syn could not finish processing this recording",
    "raw/recording-source.mp4",
):
    if needle not in prompt:
        errors.append(f"partial agent prompt missing expected content: {needle}")

if not zip_path.is_file() or zip_path.stat().st_size == 0:
    errors.append("partial packet zip is missing")
else:
    root = packet.name
    with zipfile.ZipFile(zip_path) as archive:
        names = set(archive.namelist())
    for relative in ("summary.md", "transcript.md", "agent-prompt.md", "manifest.json", "recording.mp4"):
        if f"{root}/{relative}" not in names:
            errors.append(f"partial packet zip is missing {relative}")
    if any(name.startswith(f"{root}/raw/") for name in names):
        errors.append("partial packet default zip includes raw sources")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

PAUSED_LOG="$WORK_DIR/paused-fixture.log"
"$APP_BINARY" --syn-paused-packet-fixture "$PAUSE_SEGMENT_A" "$PAUSE_SEGMENT_B" --output-root "$FIXTURE_ROOT" 2>&1 | tee "$PAUSED_LOG"

PAUSED_PACKET_DIR="$(awk -F= '/^SYN_PAUSED_FIXTURE_PACKET=/{print $2}' "$PAUSED_LOG" | tail -n 1)"
PAUSED_STATUS="$(awk -F= '/^SYN_PAUSED_FIXTURE_STATUS=/{print $2}' "$PAUSED_LOG" | tail -n 1)"

if [[ -z "$PAUSED_PACKET_DIR" || ! -d "$PAUSED_PACKET_DIR" ]]; then
  echo "paused fixture did not produce a packet directory" >&2
  exit 1
fi

if [[ "$PAUSED_STATUS" == "failed" ]]; then
  echo "paused fixture failed" >&2
  exit 1
fi

paused_required_paths=(
  "$PAUSED_PACKET_DIR/recording.mp4"
  "$PAUSED_PACKET_DIR/manifest.json"
  "$PAUSED_PACKET_DIR/raw/recording-source.mp4"
  "$PAUSED_PACKET_DIR/raw/capture-session.json"
  "$PAUSED_PACKET_DIR/raw/active-window-samples.json"
)

for path in "${paused_required_paths[@]}"; do
  if [[ ! -s "$path" ]]; then
    echo "missing or empty paused packet artifact: $path" >&2
    exit 1
  fi
done

verify_mp4_media_contract "$PAUSED_PACKET_DIR/recording.mp4" "paused recording.mp4"
verify_mp4_media_contract "$PAUSED_PACKET_DIR/raw/recording-source.mp4" "paused raw recording-source.mp4"

python3 - "$PAUSED_PACKET_DIR" <<'PY'
import json
import pathlib
import sys

packet = pathlib.Path(sys.argv[1])
manifest = json.loads((packet / "manifest.json").read_text())
raw_session = json.loads((packet / "raw/capture-session.json").read_text())
errors = []

if len(manifest.get("pauses", [])) != 1:
    errors.append("paused fixture manifest should contain exactly one pause interval")
if len(raw_session.get("pauses", [])) != 1:
    errors.append("paused fixture raw capture session should contain exactly one pause interval")
duration = manifest.get("duration", 0)
if not (4.5 <= duration <= 6.8):
    errors.append(f"paused fixture duration should include only recorded segments, got {duration:.3f}s")
pause = manifest.get("pauses", [{}])[0]
if not pause.get("startedAt") or not pause.get("endedAt"):
    errors.append("pause interval is missing timestamps")
if manifest["files"].get("activeWindowSamples") != "raw/active-window-samples.json":
    errors.append("paused fixture manifest is missing active-window sample path")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

INTERRUPTED_DIR="$WORK_DIR/interrupted-packet"
SEGMENT_INTERRUPTED_DIR="$WORK_DIR/segment-only-region-recording"
EMPTY_INTERRUPTED_DIR="$WORK_DIR/empty-interrupted-packet"
RECOVERY_HISTORY="$WORK_DIR/recovery-history.json"
/usr/bin/ditto "$PACKET_DIR" "$INTERRUPTED_DIR"
mkdir -p "$SEGMENT_INTERRUPTED_DIR/raw/segments"
mkdir -p "$EMPTY_INTERRUPTED_DIR/raw/segments"
cp "$PACKET_DIR/raw/recording-source.mp4" "$SEGMENT_INTERRUPTED_DIR/raw/segments/segment-001.mp4"
cp "$PACKET_DIR/raw/pointer-events.json" "$SEGMENT_INTERRUPTED_DIR/raw/pointer-events.json"
rm -f \
  "$INTERRUPTED_DIR/manifest.json" \
  "$INTERRUPTED_DIR/recording.mp4" \
  "$INTERRUPTED_DIR/transcript.md" \
  "$INTERRUPTED_DIR/summary.md" \
  "$INTERRUPTED_DIR/agent-prompt.md"

python3 - "$INTERRUPTED_DIR" "$SEGMENT_INTERRUPTED_DIR" "$EMPTY_INTERRUPTED_DIR" "$RECOVERY_HISTORY" <<'PY'
import json
import pathlib
import sys
import uuid
from datetime import datetime, timezone

interrupted = pathlib.Path(sys.argv[1])
segment_only = pathlib.Path(sys.argv[2])
empty = pathlib.Path(sys.argv[3])
history = pathlib.Path(sys.argv[4])
raw_session = json.loads((interrupted / "raw/capture-session.json").read_text())

def file_url(path: pathlib.Path) -> str:
    return path.resolve().as_uri()

history.write_text(json.dumps([
    {
        "id": raw_session["packetID"],
        "title": raw_session["title"],
        "createdAt": raw_session["createdAt"],
        "duration": 0,
        "status": "processing",
        "folderURL": file_url(interrupted),
        "zipURL": file_url(interrupted.with_suffix(".zip")),
    },
    {
        "id": str(uuid.uuid4()).upper(),
        "title": "segment only region recording",
        "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "duration": 0,
        "status": "failed",
        "folderURL": file_url(segment_only),
        "zipURL": file_url(segment_only.with_suffix(".zip")),
    },
    {
        "id": str(uuid.uuid4()).upper(),
        "title": "Interrupted empty recording",
        "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "duration": 0,
        "status": "processing",
        "folderURL": file_url(empty),
        "zipURL": file_url(empty.with_suffix(".zip")),
    },
], indent=2))
PY

RECOVERY_LOG="$WORK_DIR/recovery.log"
"$APP_BINARY" --syn-recover-history-fixture "$RECOVERY_HISTORY" 2>&1 | tee "$RECOVERY_LOG"

python3 - "$RECOVERY_HISTORY" "$INTERRUPTED_DIR" "$SEGMENT_INTERRUPTED_DIR" "$EMPTY_INTERRUPTED_DIR" <<'PY'
import json
import pathlib
import sys

history = pathlib.Path(sys.argv[1])
interrupted = pathlib.Path(sys.argv[2])
segment_only = pathlib.Path(sys.argv[3])
empty = pathlib.Path(sys.argv[4])
packets = json.loads(history.read_text())
statuses = [packet["status"] for packet in packets]
errors = []

if statuses != ["partial", "partial", "failed"]:
    errors.append(f"unexpected recovered statuses: {statuses}")
if "Interrupted Recording" not in (interrupted / "summary.md").read_text():
    errors.append("partial interrupted packet did not get a summary note")
if "Retry processing" not in (interrupted / "summary.md").read_text():
    errors.append("partial interrupted packet note does not mention retry")
if "fallback capture metadata" not in (segment_only / "summary.md").read_text():
    errors.append("segment-only interrupted packet note does not mention fallback metadata")
if "Interrupted Recording" not in (empty / "summary.md").read_text():
    errors.append("failed interrupted packet did not get a summary note")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

RETRY_LOG="$WORK_DIR/retry.log"
"$APP_BINARY" --syn-retry-packet-fixture "$SEGMENT_INTERRUPTED_DIR" 2>&1 | tee "$RETRY_LOG"

RETRY_PACKET_DIR="$(awk -F= '/^SYN_RETRY_FIXTURE_PACKET=/{print $2}' "$RETRY_LOG" | tail -n 1)"
RETRY_STATUS="$(awk -F= '/^SYN_RETRY_FIXTURE_STATUS=/{print $2}' "$RETRY_LOG" | tail -n 1)"

if [[ "$RETRY_PACKET_DIR" != "$SEGMENT_INTERRUPTED_DIR" ]]; then
  echo "retry fixture did not process the segment-only packet" >&2
  exit 1
fi

if [[ "$RETRY_STATUS" == "failed" ]]; then
  echo "retry fixture failed for segment-only packet" >&2
  exit 1
fi

retry_required_paths=(
  "$SEGMENT_INTERRUPTED_DIR/raw/recording-source.mp4"
  "$SEGMENT_INTERRUPTED_DIR/recording.mp4"
  "$SEGMENT_INTERRUPTED_DIR/transcript.md"
  "$SEGMENT_INTERRUPTED_DIR/summary.md"
  "$SEGMENT_INTERRUPTED_DIR/agent-prompt.md"
  "$SEGMENT_INTERRUPTED_DIR/manifest.json"
)

for path in "${retry_required_paths[@]}"; do
  if [[ ! -s "$path" ]]; then
    echo "missing or empty retried packet artifact: $path" >&2
    exit 1
  fi
done

verify_mp4_media_contract "$SEGMENT_INTERRUPTED_DIR/recording.mp4" "retried recording.mp4"
verify_mp4_media_contract "$SEGMENT_INTERRUPTED_DIR/raw/recording-source.mp4" "retried raw recording-source.mp4"

python3 - "$SEGMENT_INTERRUPTED_DIR" <<'PY'
import json
import pathlib
import sys

packet = pathlib.Path(sys.argv[1])
manifest = json.loads((packet / "manifest.json").read_text())
errors = []

if manifest["files"].get("rawCaptureSession") is not None:
    errors.append("segment-only retry manifest should not reference missing raw capture session")
if manifest["capture"].get("mode") != "region":
    errors.append(f"segment-only retry did not infer region mode: {manifest['capture'].get('mode')}")
notes = manifest["capture"].get("notes") or []
if not any("fallback capture metadata" in note for note in notes):
    errors.append("segment-only retry manifest is missing fallback capture metadata note")
if manifest.get("pointerEventCount", 0) < 1:
    errors.append("segment-only retry did not preserve pointer events")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

echo "Syn packet fixture smoke passed: $PACKET_DIR"
