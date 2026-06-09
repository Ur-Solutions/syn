#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Syn"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_APP_BUNDLE="${STAGED_APP_BUNDLE:-$HOME/Applications/$APP_NAME.app}"
OUTPUT_PATH="${1:-}"
STATUS_PATH="${SYN_UI_STATUS_PATH:-}"
WINDOW_TITLE="${SYN_UI_WINDOW_TITLE:-}"

if [[ -z "$WINDOW_TITLE" && "${SYN_UI_SHOW_REGION_SELECTOR:-0}" == "1" ]]; then
  WINDOW_TITLE="Syn Region Selection"
fi
if [[ -z "$WINDOW_TITLE" && "${SYN_UI_SHOW_WINDOW_SELECTOR:-0}" == "1" ]]; then
  WINDOW_TITLE="Syn Window Selection Target"
fi
if [[ -z "$WINDOW_TITLE" && "${SYN_UI_SHOW_CANVAS_TOOLBAR:-0}" == "1" ]]; then
  WINDOW_TITLE="Syn Canvas"
fi

if [[ ! -d "$STAGED_APP_BUNDLE" ]]; then
  echo "Syn app bundle is missing at $STAGED_APP_BUNDLE"
  echo "Run ./script/build_and_run.sh --verify first."
  exit 1
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  mkdir -p build/ui-captures
  OUTPUT_PATH="build/ui-captures/syn-ui-$(date +%Y%m%d-%H%M%S).png"
else
  mkdir -p "$(dirname "$OUTPUT_PATH")"
fi

if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi

if [[ -z "$STATUS_PATH" ]]; then
  STATUS_PATH="${OUTPUT_PATH%.png}.status.txt"
fi
if [[ "$STATUS_PATH" != /* ]]; then
  STATUS_PATH="$PWD/$STATUS_PATH"
fi

launch_args=(--syn-permission-status-output "$STATUS_PATH")
if [[ "${SYN_UI_SHOW_SETTINGS:-0}" == "1" ]]; then
  launch_args+=(--syn-show-settings-window)
elif [[ "${SYN_UI_SHOW_HUD:-0}" == "1" ]]; then
  launch_args+=(--syn-show-main-window --syn-show-recording-hud-fixture)
elif [[ "${SYN_UI_SHOW_CANVAS_TOOLBAR:-0}" == "1" ]]; then
  launch_args+=(--syn-show-main-window --syn-show-recording-hud-fixture --syn-show-canvas-toolbar-fixture)
elif [[ "${SYN_UI_SHOW_PROCESSING_HUD:-0}" == "1" ]]; then
  launch_args+=(--syn-show-main-window --syn-show-processing-hud-fixture)
elif [[ "${SYN_UI_SHOW_COMPLETION_HUD:-0}" == "1" ]]; then
  launch_args+=(--syn-show-completion-hud-fixture)
elif [[ "${SYN_UI_SHOW_REGION_SELECTOR:-0}" == "1" ]]; then
  launch_args+=(--syn-show-region-selector-fixture)
elif [[ "${SYN_UI_SHOW_WINDOW_SELECTOR:-0}" == "1" ]]; then
  launch_args+=(--syn-show-window-selector-fixture)
elif [[ "${SYN_UI_SHOW_CHROME_TAB_SELECTOR:-0}" == "1" ]]; then
  launch_args+=(--syn-show-chrome-tab-selector-fixture)
elif [[ "${SYN_UI_SHOW_VIDEO_EDITOR:-0}" == "1" ]]; then
  launch_args+=(--syn-show-video-editor-fixture)
else
  launch_args+=(--syn-show-main-window)
fi

if [[ "${SYN_UI_SHOW_PICKER:-0}" == "1" ]]; then
  launch_args+=(--syn-show-capture-picker)
fi
if [[ -n "${SYN_UI_VIDEO_EDITOR_RECORDING:-}" ]]; then
  launch_args+=(--syn-video-editor-recording "$SYN_UI_VIDEO_EDITOR_RECORDING")
fi
if [[ "${SYN_UI_REQUEST_MICROPHONE:-0}" == "1" ]]; then
  launch_args+=(--syn-request-microphone)
fi

attach_only="${SYN_UI_ATTACH_ONLY:-0}"

FIXTURE_WINDOW_PID=""
if [[ "${SYN_UI_SHOW_WINDOW_SELECTOR:-0}" == "1" ]]; then
  /usr/bin/swift "$ROOT_DIR/script/selection_fixture_window.swift" >/tmp/syn-selection-fixture-window.log 2>&1 &
  FIXTURE_WINDOW_PID=$!
  sleep 1
fi

/usr/bin/caffeinate -u -t 10 >/dev/null 2>&1 &
CAFFEINATE_PID=$!
cleanup() {
  kill "$CAFFEINATE_PID" >/dev/null 2>&1 || true
  wait "$CAFFEINATE_PID" >/dev/null 2>&1 || true
  if [[ -n "$FIXTURE_WINDOW_PID" ]]; then
    kill "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
    wait "$FIXTURE_WINDOW_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$attach_only" != "1" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$STAGED_APP_BUNDLE" --args "${launch_args[@]}"
fi

window_info=""
for _ in {1..30}; do
  window_info="$(SYN_UI_WINDOW_TITLE="$WINDOW_TITLE" /usr/bin/swift -e 'import CoreGraphics; import Foundation; struct Match { let id: Any; let x: Int; let y: Int; let width: Int; let height: Int; var area: Int { width * height } }; let titleFilter = ProcessInfo.processInfo.environment["SYN_UI_WINDOW_TITLE"] ?? ""; let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []; let matches: [Match] = list.compactMap { w in guard (w[kCGWindowOwnerName as String] as? String) == "Syn", let id = w[kCGWindowNumber as String], let bounds = w[kCGWindowBounds as String] as? [String: Any] else { return nil }; let title = w[kCGWindowName as String] as? String ?? ""; guard titleFilter.isEmpty || title == titleFilter else { return nil }; let x = Int((bounds["X"] as? NSNumber)?.doubleValue ?? 0); let y = Int((bounds["Y"] as? NSNumber)?.doubleValue ?? 0); let width = Int((bounds["Width"] as? NSNumber)?.doubleValue ?? 0); let height = Int((bounds["Height"] as? NSNumber)?.doubleValue ?? 0); return Match(id: id, x: x, y: y, width: width, height: height) }; if let match = matches.sorted(by: { $0.area > $1.area }).first { print("\(match.id) \(match.x) \(match.y) \(match.width) \(match.height)") }' 2>/dev/null | tail -n 1)"
  if [[ -n "$window_info" ]]; then
    break
  fi
  sleep 0.2
done

if [[ -z "$window_info" ]]; then
  echo "Could not find an onscreen Syn window to capture."
  exit 1
fi

read -r window_id window_x window_y window_width window_height <<< "$window_info"

if [[ "${SYN_UI_REQUEST_MICROPHONE:-0}" == "1" ]]; then
  for _ in {1..60}; do
    if [[ -s "$STATUS_PATH" ]] && ! grep -q '^SYN_PERMISSION_MICROPHONE=not_determined$' "$STATUS_PATH"; then
      break
    fi
    sleep 0.5
  done
else
  sleep 1
fi

if ! /usr/sbin/screencapture -x -o -l "$window_id" "$OUTPUT_PATH"; then
  full_output="${OUTPUT_PATH%.png}.full.png"
  /usr/sbin/screencapture -x "$full_output"
  /usr/bin/sips \
    --cropToHeightWidth "$window_height" "$window_width" \
    --cropOffset "$window_y" "$window_x" \
    "$full_output" \
    --out "$OUTPUT_PATH" >/dev/null
  rm -f "$full_output"
  echo "SYN_UI_SCREENSHOT_FALLBACK=full-crop"
fi

echo "SYN_UI_SCREENSHOT=$OUTPUT_PATH"
echo "SYN_UI_WINDOW_ID=$window_id"
echo "SYN_UI_WINDOW_BOUNDS=$window_x,$window_y,$window_width,$window_height"
if [[ -n "$WINDOW_TITLE" ]]; then
  echo "SYN_UI_WINDOW_TITLE=$WINDOW_TITLE"
fi
if [[ -s "$STATUS_PATH" ]]; then
  echo "SYN_UI_STATUS=$STATUS_PATH"
  /bin/cat "$STATUS_PATH"
else
  if [[ "$attach_only" == "1" && -x "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
    "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME" --syn-permission-status-fixture >"$STATUS_PATH" 2>/dev/null || true
  fi
  if [[ -s "$STATUS_PATH" ]]; then
    echo "SYN_UI_STATUS=$STATUS_PATH"
    /bin/cat "$STATUS_PATH"
  else
    echo "SYN_UI_STATUS_MISSING=$STATUS_PATH"
  fi
fi
