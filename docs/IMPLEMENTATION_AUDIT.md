# Syn Implementation Audit

Source documents:

- `/Users/trmd/Atlas/vault/00 Tormod/Syn.md`
- `docs/SPEC_CORROBORATION.md`

Last updated: 2026-06-04

## Current Status

The corroborated MVP is implemented and has fresh automated verification on June 4, 2026.

Latest broad verifier:

- Command: `./script/smoke_packet_fixture.sh`
- Result: passed
- Packet: `build/fixture-packets/fixture-1780553877-57E09280-15FC-4F58-9737-9F120480D954`
- Partial failure packet: `build/fixture-packets/partial-failure-fixture-1780553917-F7FA5417-5BE9-4D65-A3DE-A477944D3BEE`
- Paused packet: `build/fixture-packets/paused-fixture-1780553917-02CC8A3B-8631-4AA1-90BB-6F9E78D99A33`
- OCR fixture packet: `build/fixture-packets/ocr-fixture-1780553877-0EFE141B-187F-42E8-AD43-4257D3AED292`
- Capture picker photograb: `build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png`
- Compact zip action photograb: `build/ui-captures/syn-compact-zip-action-2026-06-04.png`
- Video edit panel photograb: `build/ui-captures/syn-video-edit-panel-final-2026-06-04.png`
- Annotation HUD photograb: `build/ui-captures/syn-recording-hud-annotations-current-2026-06-04.png`
- Project context Settings photograb: `build/ui-captures/syn-settings-project-context-2026-06-04.png`

The broad verifier covers packet artifact generation, bundled Whisper transcription, local Vision OCR metadata, OpenAI frame planning with OCR text, semantic timeline/segment artifact generation, Claude Opus summary generation with OCR frame metadata, final processed video, click bubble rendering, drawing/annotation metadata capture, annotation burn-in rendering, annotation manifest and agent-prompt metadata, pointer metadata, selected/compressed frames, candidate-frame metadata, default zip excluding raw sources, optional raw-inclusive zip creation, compact agent-facing zip creation, non-destructive video trimming, local project context snapshot generation, multiple agent prompt profiles, partial failure packet creation, retry, pause/resume segment merging, active-window padded rendering, Smart Region cursor-following crop rendering, synthetic all-screens compositing, Chrome tab parsing/metadata, history actions, Keychain fixture behavior, permission-status reporting, seven-mode capture picker contract, and hotkey disambiguation.

Latest annotation verifier:

- Command set:
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-annotation-recorder-fixture`
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-annotation-render-fixture <fixture.mp4>`
  - `./script/smoke_packet_fixture.sh`
  - `SYN_UI_SHOW_HUD=1 SYN_UI_WINDOW_TITLE="Syn Recording" ./script/capture_syn_ui.sh build/ui-captures/syn-recording-hud-annotations-current-2026-06-04.png`
- Result: all passed
- Evidence:
  - `SYN_ANNOTATION_RECORDER_FIXTURE=passed`, `SYN_ANNOTATION_RECORDER_TOOLS=rectangle,arrow,pen`, `SYN_ANNOTATION_RECORDER_PAUSED_IGNORED=yes`, and `SYN_ANNOTATION_RECORDER_CLEAR=passed`.
  - `SYN_ANNOTATION_RENDER_FIXTURE=passed`, `SYN_ANNOTATION_RENDERED_COUNT=3`, `SYN_ANNOTATION_MAPPED_COUNT=3`, and `SYN_ANNOTATION_COLOR_PIXELS=16471`.
  - Latest smoke packet `build/fixture-packets/fixture-1780546761-C9D2CD4B-50B6-4F6C-816E-E3F5AF8547A1` has `annotationCount=3`, `annotationMapping.mappedStrokeCount=3`, `annotationMapping.renderedStrokeCount=3`, and `raw/annotations.json` with rectangle, arrow, and pen strokes mapped to final video coordinates.
  - `agent-prompt.md` includes `raw/annotations.json` and `Annotations: 3 mapped, 0 unmapped, 3 drawn overlays rendered`.
  - `build/ui-captures/syn-recording-hud-annotations-current-2026-06-04.png` shows the HUD controls for pen, rectangle, arrow, clear, pause, and stop. Its status sidecar reports Microphone, Screen Recording, and Accessibility all granted.

Latest Chrome tab verifier:

- Command set:
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-chrome-tab-fixture`
  - `./script/smoke_packet_fixture.sh`
  - `./script/live_capture_fixture.sh chromeTab --duration 1`
  - `SYN_UI_SHOW_PICKER=1 ./script/capture_syn_ui.sh build/ui-captures/syn-capture-picker-chrome-tab-2026-06-04.png`
  - `SYN_UI_SHOW_CHROME_TAB_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-chrome-tab-selector-fixture-final-2026-06-04.png`
- Result: deterministic fixtures and live raw Chrome Tab capture passed
- Evidence:
  - `SYN_CHROME_TAB_FIXTURE=passed`
  - `SYN_CHROME_TAB_COUNT=2`
  - `SYN_CHROME_TAB_METADATA=passed`
  - `./script/live_capture_fixture.sh chromeTab --duration 1` produced `build/live-capture-fixtures/live-chromeTab-fixture-1780553828-255D6723-1C86-4308-9957-A9CA7E41496B` with `SYN_LIVE_FIXTURE_VERIFICATION=passed`, `SYN_LIVE_FIXTURE_STATUS=partial`, and `SYN_LIVE_FIXTURE_PROCESSED=false`.
  - The live Chrome packet's `raw/capture-session.json` records `mode: chromeTab`, `appName: Google Chrome`, `chromeTab.url: about:blank`, `chromeTab.windowIndex: 1`, `chromeTab.tabIndex: 1`, and a resolved `windowID`.
  - `ffprobe` verified the live Chrome raw `recording-source.mp4` contains H.264 video and AAC audio.
  - `build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png` shows the seven-mode picker including Chrome Tab and Smart Region.
  - `build/ui-captures/syn-chrome-tab-selector-fixture-final-2026-06-04.png` shows the Chrome tab selector UI.

The Chrome verifiers cover tab-list parsing, tab metadata persistence, capture metadata encoding, picker contract inclusion, the signed app's Apple Events entitlement/usage-description build path, real Google Chrome tab activation, real ScreenCaptureKit window capture, and raw packet metadata for Chrome Tab mode. If macOS privacy state is reset, the first live Chrome run may ask the user to grant Syn Automation access to Google Chrome again.

Latest Smart Region verifier:

- Command set:
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-smart-region-render-fixture <fixture.mp4>`
  - `./script/smoke_packet_fixture.sh`
  - `./script/live_capture_fixture.sh smartRegion --duration 1`
  - `SYN_UI_SHOW_PICKER=1 ./script/capture_syn_ui.sh build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png`
- Result: all passed
- Evidence:
  - `SYN_SMART_REGION_RENDER_FIXTURE=passed`, `SYN_SMART_REGION_RENDER_SIZE=410x202`, `SYN_SMART_REGION_RENDERED_CLICKS=1`, and `SYN_SMART_REGION_RENDER_INTERVALS=2`.
  - `SYN_CAPTURE_PICKER_MODE_TITLES=Screen,All Screens,Chrome Tab,Active Window,Select Window,Region,Smart Region`.
  - `./script/live_capture_fixture.sh smartRegion --duration 1` produced `build/live-capture-fixtures/live-smartRegion-fixture-1780549096-BD75BB00-1743-4DF4-BB9B-8B3C4E967897` with `SYN_LIVE_FIXTURE_VERIFICATION=passed`.
  - The live packet's `raw/capture-session.json` records `mode: smartRegion`, a full-display `outputSize` of 6144x2560, and a stored `smartRegion` rectangle of 3072x1280 at x=1536, y=640.
  - `ffprobe` verified the live raw `recording-source.mp4` contains H.264 video and AAC audio.
  - `build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png` shows the Smart Region tile in the picker; its status sidecar reports Microphone, Screen Recording, and Accessibility all granted.

Latest video editing verifier:

- Command set:
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-video-trim-fixture <fixture.mp4>`
  - `./script/smoke_packet_fixture.sh`
  - `SYN_UI_SHOW_VIDEO_EDITOR=1 SYN_UI_VIDEO_EDITOR_RECORDING=<fixture.mp4> ./script/capture_syn_ui.sh build/ui-captures/syn-video-edit-panel-final-2026-06-04.png`
- Result: all passed
- Evidence:
  - `SYN_VIDEO_TRIM_FIXTURE=passed`, `SYN_VIDEO_TRIM_DURATION=3.000`, and `SYN_VIDEO_TRIM_MANIFEST=updated`.
  - The trim path creates `recording-edited.mp4` beside `recording.mp4` without changing `recording.mp4` or `raw/`.
  - `PacketManifest.files.editedRecording` records the edited MP4 path after export.
  - `build/ui-captures/syn-video-edit-panel-final-2026-06-04.png` shows the packet detail trim panel with start/end inputs and `Save Trimmed Copy`; its status sidecar reports Microphone, Screen Recording, and Accessibility all granted.

Latest compact packet verifier:

- Command set:
  - `build/DerivedData/Build/Products/Debug/Syn.app/Contents/MacOS/Syn --syn-raw-zip-fixture`
  - `./script/smoke_packet_fixture.sh`
  - `SYN_UI_SHOW_VIDEO_EDITOR=1 SYN_UI_VIDEO_EDITOR_RECORDING=<fixture.mp4> ./script/capture_syn_ui.sh build/ui-captures/syn-compact-zip-action-2026-06-04.png`
- Result: all passed
- Evidence:
  - `SYN_RAW_ZIP_FIXTURE=passed`, `SYN_COMPACT_ZIP_INCLUDES_AGENT_FILES=yes`, and `SYN_COMPACT_ZIP_EXCLUDES_HEAVY_FILES=yes`.
  - The compact zip fixture includes `agent-prompt.md`, `transcript.md`, `summary.md`, `manifest.json`, `frames/candidates/metadata.json`, and compressed frames.
  - The compact zip fixture excludes `recording.mp4`, `recording-edited.mp4`, `frames/full/*`, and `raw/*`.
  - History actions verify compact zip creation records `PacketManifest.files.compactZip`, exposes `commandPacketCompactZipURL`, and deletes the sibling compact zip when the packet is deleted.
  - `build/ui-captures/syn-compact-zip-action-2026-06-04.png` shows `Create Compact Zip` in the packet detail action row; its status sidecar reports Microphone, Screen Recording, and Accessibility all granted.

Latest live raw capture verifier:

- Command set:
  - `./script/live_capture_fixture.sh screen --duration 1`
  - `./script/live_capture_fixture.sh allScreens --duration 1`
  - `./script/live_capture_fixture.sh activeWindowFollow --duration 1`
  - `./script/live_capture_fixture.sh selectedWindow --duration 1`
  - `./script/live_capture_fixture.sh region --duration 1`
  - `./script/live_capture_fixture.sh smartRegion --duration 1`
- Result: all passed with `SYN_LIVE_FIXTURE_VERIFICATION=passed`
- Packets:
  - `build/live-capture-fixtures/live-screen-fixture-1780535587-36B87589-2098-4B86-9557-470B19CC674F`
  - `build/live-capture-fixtures/live-allScreens-fixture-1780538681-16264153-7E19-42E6-8C19-707CD6034D48`
  - `build/live-capture-fixtures/live-activeWindowFollow-fixture-1780535594-AA4FEC1C-4CE4-4FE0-A8E3-C4A7501E1830`
  - `build/live-capture-fixtures/live-selectedWindow-fixture-1780535601-C5A6CC6A-7101-478B-B96A-DCB7AFD2A5A5`
  - `build/live-capture-fixtures/live-region-fixture-1780535607-636A8BC7-884F-4DDE-9EC3-DD89243CABFE`
  - `build/live-capture-fixtures/live-smartRegion-fixture-1780549096-BD75BB00-1743-4DF4-BB9B-8B3C4E967897`
- Post-live UI photograb: `build/ui-captures/syn-main-after-live-raw-modes-2026-06-04.png`

The live raw verifier stages the signed app at `/Users/trmd/Applications/Syn.app`, records through the real ScreenCaptureKit and microphone permission path, and verifies the packet folder, `raw/recording-source.mp4`, `raw/capture-session.json`, `raw/pointer-events.json`, `raw/active-window-samples.json`, raw H.264 video, raw AAC audio, summary, and agent prompt for each MVP capture mode plus Smart Region. The latest all-screens live packet recorded three display streams into one virtual desktop canvas and verified the raw H.264 stream dimensions matched capture metadata at 3840x946. Raw ScreenCaptureKit frame rates may vary by source; the broad packet smoke verifies final processed `recording.mp4` output at 30 FPS.

Latest hotkey race verifier:

- Command set:
  - `./script/hotkey_fixture.sh`
  - `./script/live_hotkey_fixture.sh fast-held-r`
  - `./script/live_hotkey_fixture.sh suffix-r`
  - `./script/live_hotkey_fixture.sh medium-suffix-r`
  - `./script/live_hotkey_fixture.sh slow-suffix-r`
  - `./script/live_hotkey_fixture.sh repeat`
- Result: all passed
- Evidence:
  - `./script/hotkey_fixture.sh` includes the repeat-deadline regression where repeat reaches its deadline, drains input, and a queued `R` still resolves to picker.
  - `./script/live_hotkey_fixture.sh` requires exactly one expected action and photograbs the resulting Syn window for each live shortcut run.
  - `GlobalHotkeyService` uses HID, session, annotated-session, and AppKit R-key observation plus physical R polling to bias `Left Shift + Right Shift + R` toward picker when macOS drops or reorders key events.
  - `build/live-hotkey-fixture/fast-held-r-events.log` shows `R` observed while both Shifts are down, then `action picker`; the latest action log contains exactly `picker`.
  - `build/live-hotkey-fixture/suffix-r-events.log` shows `pending repeat generation=4`, then an `R` key event resolves to `action picker`; the latest action log contains exactly `picker`.
  - `build/live-hotkey-fixture/medium-suffix-r-events.log` shows `pending repeat generation=4`, `pending repeat input drain generation=4`, then `action picker`; the latest action log contains exactly `picker`, proving picker wins for human-paced suffix timing.
  - `build/live-hotkey-fixture/slow-suffix-r-events.log` shows `pending repeat input drain generation=4` before `action repeat generation=4`; the latest action log contains exactly `repeat`.
  - `build/live-hotkey-fixture/repeat-events.log` shows `pending repeat input drain generation=4` before `action repeat generation=4`; the latest action log contains exactly `repeat`, proving deliberate repeat still works after the drain.
  - `build/ui-captures/syn-live-hotkey-fast-held-r.png`, `build/ui-captures/syn-live-hotkey-suffix-r.png`, and `build/ui-captures/syn-live-hotkey-medium-suffix-r.png` show the picker opening for the picker shortcut variants.
  - `build/ui-captures/syn-live-hotkey-slow-suffix-r.png` and `build/ui-captures/syn-live-hotkey-repeat.png` show repeat resolving without opening the picker.

Latest processed selector verifier:

- Command set:
  - `./script/selector_recording_fixture.sh region 1.0 --process`
  - `./script/selector_recording_fixture.sh selectedWindow 1.0 --process`
- Result: both passed
- Packets:
  - `/Users/trmd/Movies/Syn/2026-06-04/region-recording-03-34-39`
  - `/Users/trmd/Movies/Syn/2026-06-04/select-window-recording-03-35-23`
- Post-run UI photograb: `build/ui-captures/syn-main-after-processed-selector-current-2026-06-04.png`

The processed selector verifier stages the signed app, drives the actual region/selected-window selector confirmation path, records through ScreenCaptureKit and microphone permissions, runs bundled Whisper, OpenAI semantic frame planning, and Claude Opus summary generation, then verifies raw H.264/AAC capture, raw capture-session mode, processed 30 FPS H.264/AAC output, provider/model metadata, selected frame files, prompt sections, and default zip selected-frame inclusion while excluding `raw/`.

Latest draggable region verifier:

- Command set:
  - `./script/selector_input_fixture.sh region`
  - `./script/selector_confirm_fixture.sh region`
  - `SYN_UI_SHOW_REGION_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-region-selector-draggable-2026-06-04.png`
- Result: both passed
- Evidence:
  - `./script/selector_input_fixture.sh region` launches the actual region overlay, photograbs `build/ui-captures/syn-selector-input-region-before.png`, drives `mouseDown`, `mouseDragged`, `mouseUp`, then drags the selected rectangle before Return.
  - The latest selector input callback logged `region 2908,1172,520,360 display=4 moved=true`, proving the existing rectangle moved before confirmation.
  - `./script/selector_confirm_fixture.sh region` still passed after the drag behavior change, proving existing confirm-only region selection remains intact.
  - `build/ui-captures/syn-region-selector-draggable-2026-06-04.png` shows the selected rectangle with dimensions plus Confirm/Cancel controls; its sidecar reports Microphone, Screen Recording, and Accessibility all granted.

## Requirement Coverage

| Requirement | Status | Evidence |
| --- | --- | --- |
| Native macOS app using Swift/SwiftUI with AppKit interop | Implemented | `Syn.xcodeproj`, `Syn/App`, `Syn/Views`, `Syn/Services`; builds with `./script/build_and_run.sh --verify`. |
| Menu bar utility with small settings/history window | Implemented | `MenuBarView`, `MainWindowController`, `ContentView`; photograb `syn-main-after-full-smoke-hotkey-all-screens-2026-06-04.png`. |
| Two global shortcuts: picker and repeat-last | Implemented | `GlobalHotkeyService`; `./script/hotkey_fixture.sh`; live fixtures `suffix-r`, `medium-suffix-r`, `slow-suffix-r`, `held-r`, `fast-held-r`, `long-held-r`, `repeat`. Repeat resolves after the two-Shift chord is released, then runs an about one-second suffix grace/input-drain pass. |
| Picker wins over repeat when `R` follows or is held | Implemented | `fast-held-r`, `suffix-r`, `medium-suffix-r`, physical R-key polling cases, repeat-deadline input-drain regression, and photograbs `syn-live-hotkey-fast-held-r.png` / `syn-live-hotkey-suffix-r.png` / `syn-live-hotkey-medium-suffix-r.png`. |
| Repeat opens picker when there is no completed recording | Implemented | `--syn-repeat-policy-fixture` inside smoke. |
| Capture picker shows Screen, All Screens, Chrome Tab, Active Window, Select Window, Region, Smart Region, mic status, last mode, Settings | Implemented | `--syn-capture-picker-contract-fixture`; picker photograb `build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png`. |
| Screen capture | Implemented | `live_capture_fixture.sh --duration 1`; packet smoke processing fixture. |
| All-screens capture | Implemented | `live_capture_fixture.sh allScreens --duration 1`; `--syn-all-screens-render-fixture` in smoke verifies virtual desktop compositing and click mapping. |
| Chrome tab capture | Implemented | `ChromeTabService`, `CaptureMode.chromeTab`, `--syn-chrome-tab-fixture`, `./script/live_capture_fixture.sh chromeTab --duration 1`, picker/selector photograbs, and live Chrome packet `build/live-capture-fixtures/live-chromeTab-fixture-1780553828-255D6723-1C86-4308-9957-A9CA7E41496B`. |
| Active-window-follow capture, changing with frontmost window | Implemented | `ActiveWindowTracker`; `--syn-active-window-tracker-fixture`; raw live active-window fixture evidence in `USER_INPUT_REQUIRED.md`. |
| Active-window final fixed canvas from largest window plus 24 px padding | Implemented | `VideoUtilities`; `--syn-active-window-render-fixture`, smoke output `SYN_ACTIVE_WINDOW_RENDER_SIZE=868x480`. |
| Selected-window capture | Implemented | `WindowSelectionController`; selector input/recording fixtures; strengthened processed selector fixture `/Users/trmd/Movies/Syn/2026-06-04/select-window-recording-03-35-23`. |
| Drawable region capture | Implemented | `RegionSelectionController`; selector input/recording fixtures; strengthened processed selector fixture `/Users/trmd/Movies/Syn/2026-06-04/region-recording-03-34-39`. |
| Draggable region refinement before capture | Implemented | `RegionSelectionController` supports dragging inside an existing selection to move it; `./script/selector_input_fixture.sh region` requires `moved=true` after synthetic drag-move and Return; photograb `build/ui-captures/syn-region-selector-draggable-2026-06-04.png`. |
| Smart Region cursor-following crop | Implemented | `CaptureMode.smartRegion`, `ScreenCaptureRecorder`, `VideoUtilities.makeSmartRegionRenderPlan`; `--syn-smart-region-render-fixture`, `./script/live_capture_fixture.sh smartRegion --duration 1`, and picker photograb `build/ui-captures/syn-capture-picker-smart-region-verified-2026-06-04.png`. |
| Cursor visible in video | Implemented | ScreenCaptureKit configuration fixture verifies cursor enabled. |
| Clicks burned into video as expanding bubbles | Implemented | `VideoUtilities`; smoke verifies rendered click overlays and active-window click bubble rendering. |
| Pointer/click metadata stored with source and video coordinates | Implemented | `PointerEventRecorder`, `PointerEvent`, `manifest.pointerMapping`; smoke verifies mapped pointer events and raw `pointer-events.json`. |
| Microphone-only recording; no system/app audio | Implemented | `ScreenCaptureRecorder`; capture configuration fixture verifies mic enabled, system audio disabled, current-process audio excluded. |
| HUD with timer, mic level, pause/resume, stop | Implemented | `RecordingHUDView`; HUD photograbs; pause/resume fixtures. |
| Drawing/annotation overlay with rectangles, arrows, and pen strokes | Implemented | `AnnotationOverlayController`, `AnnotationRecorder`, `AnnotationModels`, HUD tool controls; `--syn-annotation-recorder-fixture`, `--syn-annotation-render-fixture`, smoke annotation manifest/prompt assertions, and HUD photograb `build/ui-captures/syn-recording-hud-annotations-current-2026-06-04.png`. |
| Pause omits video/mic from final timeline and stores intervals | Implemented | paused packet fixture verifies final duration and `manifest.pauses`. |
| Warn at 30 minutes, no hard limit | Implemented | `RecordingDurationWarning`; `--syn-duration-warning-fixture`. |
| 30 FPS H.264 MP4 with AAC audio | Implemented | smoke uses `ffprobe` on processed, raw, paused, and retried recordings. |
| `recording.mp4` is processed final; raw recordings kept under `raw/` | Implemented | `PacketProcessor`, `VideoUtilities`; smoke verifies `recording.mp4` and `raw/recording-source.mp4`. |
| Default zip excludes `raw/` | Implemented | `ZipService`; smoke verifies zip listing excludes raw sources. |
| Optional raw-inclusive zip is available separately | Implemented | `ZipService.createRawZip`, `AppState.createRawZip`, `--syn-raw-zip-fixture`, history action fixture, and photograb `build/ui-captures/syn-main-raw-zip-action-2026-06-04.png`. |
| Compact packet option | Implemented | `ZipService.createCompactZip`, `AppState.createCompactZip`, `PacketManifest.files.compactZip`, `--syn-raw-zip-fixture`, history action fixture, and photograb `build/ui-captures/syn-compact-zip-action-2026-06-04.png`. |
| Simple video editing after creation | Implemented | `VideoTrimService`, `AppState.createTrimmedRecording`, `PacketManifest.files.editedRecording`, `--syn-video-trim-fixture`, and photograb `build/ui-captures/syn-video-edit-panel-final-2026-06-04.png`. |
| Local bundled Whisper transcription | Implemented | `TranscriptionService`; smoke verifies provider `local-whisper.cpp-bundled`, model `ggml-base.en.bin`. |
| OpenAI semantic frame planning from transcript + visual-change/OCR metadata | Implemented | `FramePlanningService`; smoke verifies provider `openai-semantic`, model `gpt-5-mini`; OCR fixture verifies recognized text is available to frame metadata. |
| Automatic semantic partitioning / topic slicing | Implemented | `FramePlanningService` produces `SemanticSegment` records from transcript, visual-change, and OCR-enriched selected frames; `PacketProcessor` writes `semantic-segments.json` and `semantic-timeline.md`, records them in `manifest.json`, includes them in the default zip, and embeds `## Semantic Timeline` in `agent-prompt.md`. Latest smoke packet `fixture-1780553877-57E09280-15FC-4F58-9737-9F120480D954` verifies ordered segments, frame references, manifest paths, prompt handoff, and zip inclusion. |
| Claude Opus summary from transcript + selected compressed images | Implemented | `AIProviderService`; summary contract fixture verifies Claude text+image payload, selected-frame OCR metadata fields, and no raw audio/video attachments. |
| Candidate frames sampled every 2-3 seconds, pixel-deduped, OCR enriched, metadata only by default | Implemented | `FrameExtractor`; smoke verifies candidates, pixel differences, deterministic OCR text `SYN OCR / 4829`, and default `frames/candidates/metadata.json` only. |
| Full-resolution selected frames and compressed/downscaled LLM-ready frames | Implemented | `FrameExtractor`; smoke verifies PNG full frames, JPEG compressed frames, dimensions, bytes, and 1600 px long edge. |
| Packet contains required files and folders | Implemented | `PacketContext`, `PacketProcessor`; smoke checks `recording.mp4`, `transcript.md`, `summary.md`, `agent-prompt.md`, `manifest.json`, frames, and raw metadata. |
| Codebase connection / project setup context | Implemented | `ProjectContextService`, Settings Project Context chooser, `project-context.md`, `PacketManifest.files.projectContext`, prompt section `## Project Context`, smoke fixture packet `fixture-1780552550-C86B2A50-F02C-40B5-85D5-2027099AFEC3`, and photograb `build/ui-captures/syn-settings-project-context-2026-06-04.png`. The snapshot is metadata-only and smoke verifies secret/heavy fixture content is excluded. |
| Clipboard copies `agent-prompt.md` text and packet folder file URL | Implemented | `PacketClipboard`; smoke verifies pasteboard text and file URL. |
| Agent prompt references packet folder and zip and includes useful workflow context | Implemented | `PacketProcessor.buildAgentPrompt`; smoke verifies enriched prompt sections and paths. |
| Multiple agent prompt profiles | Implemented | `AgentPromptProfile`, Settings picker, `agent-prompts/` packet folder, `manifest.agentPromptProfile`, `--syn-prompt-profile-fixture`, smoke checks, and Settings photograb `build/ui-captures/syn-settings-prompt-profiles-2026-06-04.png`. |
| Packet storage under `~/Movies/Syn/YYYY-MM-DD/<slug>-<timestamp>/` with sibling zip | Implemented | `PacketLayout`; packet layout fixture and smoke. |
| History with status, duration, open folder, copy, reveal zip, retry, delete | Implemented | `ContentView`, `PacketHistoryStore`; history actions fixture verifies copy, missing zip hiding, delete. |
| Postprocessing failure creates partial packet and supports retry | Implemented | `writePartialFailureArtifacts`, recovery/retry fixtures; smoke verifies partial packet and segment-only retry. |
| Permissions checklist for Screen Recording, Microphone, Accessibility | Implemented | `PermissionService`, `PermissionsChecklistView`; UI photograbs and permission status fixtures. |
| API keys in macOS Keychain | Implemented | `SecretStore`, `SettingsView`; secret-store fixture and Settings photograb. |

## Deferred / Remaining Broader Scope

The following is explicitly deferred in `docs/SPEC_CORROBORATION.md` and is not counted as an MVP blocker:

- System/app audio.

## Remaining Evidence Notes

`USER_INPUT_REQUIRED.md` still lists optional physical confidence checks for actual keyboard/trackpad hardware. Automated live fixtures already post macOS keyboard and mouse events through the running app and verify the same app paths. The remaining physical checks are useful confidence checks, but they are not implementation blockers unless manual hardware behavior contradicts the automated evidence.
