# Syn

Syn is a native macOS menu bar utility for recording narrated visual feedback and turning it into an agent-ready packet.

The current repository contains the macOS app implementation, verification scripts, the specification corroboration record, and an implementation audit.

## Build And Run

```bash
./script/build_and_run.sh
```

The script stages and launches the app at `/Applications/Syn.app` so macOS privacy permissions attach to a stable app bundle. Override the location with `STAGED_APP_BUNDLE=/some/path/Syn.app ./script/build_and_run.sh` (the verification fixtures still stage their own copy under `~/Applications/Syn.app`).

When the `Apple Development: Tormod Haugland (QT5J6P28AM)` identity is available, the script uses it automatically so macOS privacy grants attach to a stable Team ID across rebuilds. It falls back to Developer ID and then `Rift Local Signing` only if Apple Development signing is unavailable. Override with `SYN_CODE_SIGN_IDENTITY="Identity Name"` if needed.

The script also sets `ENABLE_DEBUG_DYLIB=NO` for the launched debug app. This avoids a hardened-runtime library validation failure with locally signed debug dylibs while keeping normal debug symbols available.

Optional modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## Documents

- [Specification corroboration](docs/SPEC_CORROBORATION.md)
- [Implementation audit](docs/IMPLEMENTATION_AUDIT.md)
- [Testing checklist](docs/TESTING_CHECKLIST.md)
- [User input required](USER_INPUT_REQUIRED.md)

## Verification

Run the deterministic packet-processing smoke test:

```bash
./script/smoke_packet_fixture.sh
```

This builds the app with the same signing/debug-dylib settings as the launch script, creates a synthetic recording fixture, processes it through the real packet pipeline, and verifies the packet artifacts. It exercises global hotkey registration, seven-mode capture-picker contract, Chrome tab parsing/metadata, repeat-last policy, isolated status-aware Keychain secret-store behavior, bundled Whisper transcription, local Vision OCR metadata, OpenAI semantic frame planning, semantic segment/timeline artifact generation, Claude summary generation when keys are available, Claude text+image payload construction, local fallback summary structure, enriched agent prompt handoff content, multiple agent prompt profiles, local project context snapshots, final video rendering, non-destructive video trimming, drawing/annotation recorder metadata, annotation burn-in rendering, annotation manifest/prompt handoff content, 30 FPS H.264/AAC MP4 media contracts, active-window-follow padded rendering, Smart Region cursor-following crop rendering, all-screens synthetic compositing, pause/resume segment merging, visual-change metadata, selected full/compressed frame metadata, candidate frame metadata-only storage, opt-in candidate debug frame retention, default zip selected-frame inclusion, compact zip inclusion/exclusion rules, optional raw-inclusive zip creation, packet clipboard handoff, missing-zip UI hiding, pointer metadata, manifest writing, raw retry metadata, zip contents excluding raw sources, interrupted-history recovery, segment-only raw retry, and the 30-minute duration warning threshold.

Full live recording verification still requires macOS Screen Recording, Microphone, and possibly Accessibility permissions. See [User input required](USER_INPUT_REQUIRED.md).

Set `SYN_KEEP_CANDIDATE_FRAMES=1` when processing if you need debug JPEGs for every sampled candidate frame under `frames/candidates/`. The default packet keeps only `frames/candidates/metadata.json` there.

Global capture shortcuts:

- `Left Shift + Right Shift + R`: open the capture picker.
- `Left Shift + Right Shift`: press both Shift keys and release without pressing another key to repeat the last completed capture mode, or open the picker if no recording has completed yet. Repeat waits through a short suffix grace plus a brief input-drain pass, so `R` can still cancel pending repeat and open the picker when it is part of the same gesture.

These shortcuts use a low-level listen-only HID event tap on a dedicated hotkey thread, with supplemental session, annotated-session, and AppKit key monitoring for R-key events. Syn reads the left/right Shift modifier bits from each keyboard event when macOS provides them, so duplicate modifier events do not accidentally fire repeat before the picker chord. While both Shifts are held, and again during the pending repeat window, Syn polls the physical R-key state so the picker can still win if macOS does not deliver a separate R event. If the repeat timer reaches its deadline just before an R event is processed, Syn performs a short input-drain pass before firing repeat. Accessibility permission must be granted to `/Applications/Syn.app` for them to register.

App-local packet commands:

- `Command + Shift + O`: open the selected packet folder, or the latest packet if none is selected.
- `Command + Shift + C`: copy the selected/latest packet handoff.
- `Command + Option + O`: reveal the selected/latest packet zip when it exists.
- Packet detail and menu bar actions can also create/reveal a separate `-compact.zip` archive for lightweight agent handoff and a separate `-with-raw.zip` archive when raw recovery sources need to be shared. The normal default zip still excludes `raw/`.

Agent prompt profiles:

- Settings chooses the default `agent-prompt.md` handoff profile.
- Each completed packet also includes all built-in variants under `agent-prompts/`: General Coding Agent, Implementation Plan, and QA Bug Report.

Project context:

- Settings can attach one local project folder to future packets.
- When configured, each processed packet includes `project-context.md`, records it in `manifest.json` as `files.projectContext`, and embeds a bounded excerpt under `## Project Context` in `agent-prompt.md`.
- The snapshot is metadata-oriented: root path, marker files such as `Package.swift`/`package.json`, git branch/commit/status/recent commits, top-level structure, and a README excerpt. It excludes common secret/heavy entries and does not embed source files.

Semantic timeline:

- Each processed packet includes `semantic-segments.json` and `semantic-timeline.md`.
- The segments are derived from the OpenAI frame plan over transcript, visual-change metadata, and local OCR text; each segment records time bounds, a title, a summary, source, and representative frame paths.
- `manifest.json`, the default zip, and `agent-prompt.md` all reference these files so agents can navigate topic changes without requiring a separate UI.

To check the real macOS ScreenCaptureKit and microphone path without sending screen contents to AI providers:

```bash
./script/live_capture_fixture.sh --duration 1
```

This stages the signed app at `~/Applications/Syn.app`, keeps the display session awake, quits the GUI app, records a short raw screen+mic fixture through the real app bundle identity, verifies the raw packet files plus H.264/AAC streams, and stops before packet AI processing. Pass `allScreens`, `activeWindowFollow`, `selectedWindow`, `region`, or `smartRegion` as the first argument to test those raw capture modes, for example `./script/live_capture_fixture.sh smartRegion --duration 1`. Add `--process` only when the captured screen contents are safe to send through the configured OpenAI and Anthropic providers.

`chromeTab` uses macOS Automation to list and activate Google Chrome tabs. The deterministic smoke covers Chrome tab parsing and packet metadata, and `./script/live_capture_fixture.sh chromeTab --duration 1` verifies the real Chrome Tab recording path without packet AI processing. If macOS privacy state is reset, the first run may ask for permission to control Google Chrome. Add `--process` only when the active tab is safe to send through the configured AI providers.

Smart Region records the full selected display as raw source material, stores the selected rectangle in `raw/capture-session.json`, and renders the final processed video as a fixed-size crop that follows the cursor. The smoke fixture verifies the moving crop render path; the live fixture verifies the real raw capture path.

Packet detail includes a simple non-destructive trim tool. Set start/end seconds and choose `Save Trimmed Copy` to create `recording-edited.mp4` beside `recording.mp4`; `manifest.json` records the edited output path.

Compact packet zips keep agent-facing text, manifest metadata, prompt profiles, candidate metadata, and compressed frames. They exclude `raw/`, `recording.mp4`, `recording-edited.mp4`, and `frames/full/`.

To check that both required global shortcuts can register and that the left/right Shift chord logic resolves correctly:

```bash
./script/hotkey_fixture.sh
```

To post the real shortcut sequences into the running GUI session and photograb the result:

```bash
./script/live_hotkey_fixture.sh suffix-r
./script/live_hotkey_fixture.sh medium-suffix-r
./script/live_hotkey_fixture.sh slow-suffix-r
./script/live_hotkey_fixture.sh held-r
./script/live_hotkey_fixture.sh fast-held-r
./script/live_hotkey_fixture.sh long-held-r
./script/live_hotkey_fixture.sh repeat
```

`suffix-r` verifies a quick `Left Shift + Right Shift`, release, then `R` sequence opens the picker instead of repeat. `medium-suffix-r` verifies a human-paced suffix `R` still opens the picker during the longer repeat drain window. `slow-suffix-r` verifies a late `R` no longer steals the already-resolved repeat action. `held-r` verifies tapping `R` while both Shifts are still held. `fast-held-r` verifies a very short R tap while both Shifts are held still opens the picker. `long-held-r` verifies the slower human path where both Shifts are held longer before `R` is tapped. `repeat` verifies the plain two-Shift chord resolves to repeat in observer mode without starting an actual recording, including the repeat input-drain pass. Each run waits long enough to catch a late callback, requires exactly one expected action, writes an action log and fixture-only event trace under `build/live-hotkey-fixture/`, and photograbs the actual resulting Syn window.

To verify the shortcut-to-recording path without sending screen contents to AI providers:

```bash
./script/live_hotkey_recording_fixture.sh picker selectedWindow 2.5
SYN_HOTKEY_SEQUENCE=medium-suffix-r ./script/live_hotkey_recording_fixture.sh picker selectedWindow 2.5
SYN_HOTKEY_SEQUENCE=held-r ./script/live_hotkey_recording_fixture.sh picker selectedWindow 2.5
SYN_HOTKEY_SEQUENCE=fast-held-r ./script/live_hotkey_recording_fixture.sh picker selectedWindow 2.5
SYN_HOTKEY_SEQUENCE=long-held-r ./script/live_hotkey_recording_fixture.sh picker selectedWindow 2.5
./script/live_hotkey_recording_fixture.sh repeat selectedWindow 2.5
```

The recording fixture logs which shortcut action won, captures the floating HUD under `build/ui-captures/`, records a temporary selected window through the staged signed app, and stops after raw local capture. Add `--process` only when the captured contents are safe to send through the configured AI providers.

To photograb the recording HUD and canvas toolbar directly:

```bash
SYN_UI_SHOW_CANVAS_TOOLBAR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-canvas-toolbar-current.png
```

The HUD includes a Canvas Mode toggle. Canvas Mode opens a draggable toolbar below the HUD with pen, line, rectangle, ellipse, delete selected, clear, and exit controls. The discard (trash) control is a two-step confirm: the first click arms it (the icon turns red), and a second click within a few seconds discards the in-progress recording without producing a packet. The smoke fixture verifies pen, line, rectangle, and ellipse metadata plus burned-in annotation overlays in `recording.mp4`.

To photograb the capture picker directly:

```bash
SYN_UI_SHOW_PICKER=1 ./script/capture_syn_ui.sh build/ui-captures/syn-capture-picker.png
```

To photograb the packet video editor directly:

```bash
SYN_UI_SHOW_VIDEO_EDITOR=1 SYN_UI_VIDEO_EDITOR_RECORDING="$PWD/build/fixture-packets/fixture-1780550940-146CE238-4422-476B-BA65-AC429EB1EEDA/raw/recording-source.mp4" ./script/capture_syn_ui.sh build/ui-captures/syn-video-edit-panel.png
```

To photograb the Chrome tab selector with fixture data:

```bash
SYN_UI_SHOW_CHROME_TAB_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-chrome-tab-selector-fixture.png
```

To photograb the selection overlays directly:

```bash
SYN_UI_SHOW_REGION_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-region-selector-fixture.png
SYN_UI_SHOW_WINDOW_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-window-selector-fixture.png
```

The window-selector capture helper starts a temporary external fixture window so Syn can show a stable highlighted target with confirmation controls.

To verify that the selector confirmation callbacks fire without starting a real recording:

```bash
./script/selector_confirm_fixture.sh region
./script/selector_confirm_fixture.sh selectedWindow
```

To verify the selector input handlers themselves, using synthetic in-app `NSEvent` mouse/key events rather than direct auto-confirm:

```bash
./script/selector_input_fixture.sh region
./script/selector_input_fixture.sh selectedWindow
```

The region input fixture drives the overlay through `mouseDown`, `mouseDragged`, `mouseUp`, a drag-move of the selected rectangle, and Return; it fails unless the app callback logs `moved=true`. The selected-window input fixture drives hover/click selection and Return confirmation against a temporary external target window. Both fixtures photograb the visible pre-input overlay under `build/ui-captures/`.

To verify that the selector path starts and stops a real raw recording without sending live screen or microphone contents to AI providers:

```bash
./script/selector_recording_fixture.sh region
./script/selector_recording_fixture.sh selectedWindow
```

Add `--process` to run the selector-confirmed recording through the real packet processor as a safe end-to-end selector packet check:

```bash
./script/selector_recording_fixture.sh region 1.0 --process
./script/selector_recording_fixture.sh selectedWindow 1.0 --process
```

Processed selector fixtures open a local fixture window, record through the staged signed app, run bundled Whisper, OpenAI frame planning, Claude summary generation, and verify the completed packet artifacts. The verifier checks raw H.264/AAC capture, capture-session mode, processed 30 FPS H.264/AAC output, provider/model metadata, selected frame metadata and files, prompt sections, and default zip contents excluding `raw/`.

To photograb the recording HUD directly:

```bash
SYN_UI_SHOW_HUD=1 SYN_UI_WINDOW_TITLE="Syn Recording" ./script/capture_syn_ui.sh build/ui-captures/syn-recording-hud.png
```

To photograb Settings and verify the Keychain key-management UI:

```bash
SYN_UI_SHOW_SETTINGS=1 ./script/capture_syn_ui.sh build/ui-captures/syn-settings-keychain.png
```

If macOS privacy state gets confused while iterating on debug builds:

```bash
./script/diagnose_permissions.sh
./script/reset_permissions.sh
./script/build_and_run.sh --verify
```

`diagnose_permissions.sh` is read-only. It prints the staged bundle path, bundle ID, signing state, running process path, and any readable TCC rows. `reset_permissions.sh` clears Screen Recording, Microphone, and Accessibility grants for `com.trmd.syn`, so only run it when you are ready to regrant permissions.
