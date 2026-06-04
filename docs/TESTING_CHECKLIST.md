# Syn Testing Checklist

Use this as the manual QA checklist for Syn while the app is still in MVP development.

The default test target is the staged app at:

```bash
/Users/trmd/Applications/Syn.app
```

Always launch it through:

```bash
./script/build_and_run.sh --verify
```

That keeps the bundle path, bundle ID, and signing identity stable for macOS privacy permissions.

## Test Rules

- Do not run a live capture with `--process` unless the screen contents are safe to send to the configured OpenAI and Anthropic providers.
- For UI issues, create or keep a photograb under `build/ui-captures/`.
- For video issues, extract frames under `build/diagnostics/<packet-name>/`.
- When a packet looks wrong, inspect both `recording.mp4` and `raw/recording-source.mp4`.
  - If raw is wrong, the bug is capture-time.
  - If raw is good and final is wrong, the bug is processing/rendering.
- Prefer short recordings: 5-15 seconds for capture tests, 30-60 seconds for processing tests.
- Use a non-sensitive test window with obvious moving visual content and a few spoken words.

## Quick Smoke Pass

- [ ] Build and stage the app.

```bash
./script/build_and_run.sh --verify
```

Expected:

- [ ] Build succeeds.
- [ ] Syn is running from `/Users/trmd/Applications/Syn.app`.
- [ ] The menu bar extra appears.
- [ ] No second Syn instance remains running.

- [ ] Run deterministic smoke.

```bash
./script/smoke_packet_fixture.sh
```

Expected:

- [ ] Script exits 0.
- [ ] Output ends with `Syn packet fixture smoke passed: ...`.
- [ ] No fixture reports `failed`.

- [ ] Run focused real raw capture without AI.

```bash
./script/live_capture_fixture.sh screen --duration 2
./script/live_capture_fixture.sh region --duration 2
./script/live_capture_fixture.sh selectedWindow --duration 2
```

Expected:

- [ ] Each fixture exits 0.
- [ ] Each produces a partial raw packet.
- [ ] `raw/recording-source.mp4` exists and has visible content.
- [ ] `raw/capture-session.json` records the intended capture mode.

## Permission Checks

- [ ] Open Syn Overview and inspect Permissions.

Expected:

- [ ] Running app path is `/Users/trmd/Applications/Syn.app`.
- [ ] Bundle ID is `com.trmd.syn`.
- [ ] Screen Recording is `Allowed`.
- [ ] Microphone is `Allowed`.
- [ ] Accessibility is `Allowed`.
- [ ] Disabled buttons match already-granted permissions.
- [ ] Permission status is readable without stale "Needed" after grants.

- [ ] Run diagnostics.

```bash
./script/diagnose_permissions.sh
```

Expected:

- [ ] Bundle path is `/Users/trmd/Applications/Syn.app`.
- [ ] Bundle ID is `com.trmd.syn`.
- [ ] Running process path matches the staged app.
- [ ] Microphone status is granted/authorized.
- [ ] Screen Recording status is granted.
- [ ] Accessibility status is granted.

- [ ] If permissions are intentionally reset, verify re-request.

```bash
./script/reset_permissions.sh
./script/build_and_run.sh --verify
```

Expected:

- [ ] Missing permissions show as needed/not requested.
- [ ] Request buttons open the right system settings or prompt path.
- [ ] Refresh updates the UI after grants.

## UI Photograbs

- [ ] Capture the main Overview window.

```bash
SYN_UI_WINDOW_TITLE="Overview" ./script/capture_syn_ui.sh build/ui-captures/syn-overview-current.png
```

- [ ] Capture the picker.

```bash
SYN_UI_SHOW_PICKER=1 ./script/capture_syn_ui.sh build/ui-captures/syn-capture-picker-current.png
```

- [ ] Capture Settings.

```bash
SYN_UI_SHOW_SETTINGS=1 ./script/capture_syn_ui.sh build/ui-captures/syn-settings-current.png
```

- [ ] Capture the recording HUD fixture.

```bash
SYN_UI_SHOW_HUD=1 SYN_UI_WINDOW_TITLE="Syn Recording" ./script/capture_syn_ui.sh build/ui-captures/syn-recording-hud-current.png
```

- [ ] Capture the processing HUD fixture.

```bash
SYN_UI_SHOW_PROCESSING_HUD=1 SYN_UI_WINDOW_TITLE="Syn Recording" ./script/capture_syn_ui.sh build/ui-captures/syn-processing-hud-current.png
```

Expected:

- [ ] No important controls are clipped.
- [ ] Text is readable and not overlapping.
- [ ] Processing HUD says `Processing`.
- [ ] Processing HUD timer is frozen in the fixture.
- [ ] Processing HUD pause/stop/annotation controls are disabled.
- [ ] Overview processing banner also disables Pause and Stop.

## Global Shortcuts

Shortcuts:

- Picker: `Left Shift + Right Shift + R`
- Repeat last mode: `Left Shift + Right Shift`

- [ ] Run deterministic hotkey fixture.

```bash
./script/hotkey_fixture.sh
```

Expected:

- [ ] Fixture passes.
- [ ] Picker chord wins over repeat when `R` is part of the gesture.
- [ ] Repeat does not fire early before the suffix/drain window ends.

- [ ] Run live shortcut sequences.

```bash
./script/live_hotkey_fixture.sh suffix-r
./script/live_hotkey_fixture.sh medium-suffix-r
./script/live_hotkey_fixture.sh held-r
./script/live_hotkey_fixture.sh fast-held-r
./script/live_hotkey_fixture.sh long-held-r
./script/live_hotkey_fixture.sh repeat
```

Expected:

- [ ] `suffix-r`, `medium-suffix-r`, `held-r`, `fast-held-r`, and `long-held-r` open the picker.
- [ ] `repeat` resolves to repeat when a completed recording exists.
- [ ] Each fixture logs exactly one winning action.
- [ ] Each fixture photograbs the resulting Syn UI.

- [ ] Manual shortcut checks.

Expected:

- [ ] With no completed recording, both shortcuts open the picker.
- [ ] After a completed recording, two-shift repeat starts the last capture mode.
- [ ] Two-shift-plus-R opens the picker, not repeat.
- [ ] Shortcuts do not trigger while typing normal Shift-modified text in another app unless the exact chord is used.

## Capture Picker

- [ ] Open picker from menu bar.
- [ ] Open picker from `Left Shift + Right Shift + R`.

Expected:

- [ ] Picker opens quickly.
- [ ] Picker shows these modes: Screen, All Screens, Chrome Tab, Active Window, Select Window, Region, Smart Region.
- [ ] Microphone status is visible.
- [ ] Settings is reachable.
- [ ] Last mode/repeat affordance is visible when relevant.
- [ ] Escape/dismiss works.
- [ ] Choosing each mode starts the correct preflight or selector flow.

## Screen Capture

- [ ] Record a 10 second full-screen capture.

Expected:

- [ ] HUD appears.
- [ ] Timer advances while recording.
- [ ] Mic meter moves when speaking.
- [ ] Stop ends recording.
- [ ] Processing starts.
- [ ] Timer no longer advances after Stop.
- [ ] Packet appears in History.
- [ ] `raw/recording-source.mp4` contains visible screen content.
- [ ] `recording.mp4` contains visible final content.
- [ ] Transcript exists.
- [ ] Summary exists.
- [ ] Manifest records mode `screen`.

## All Screens Capture

- [ ] Record 5-10 seconds with visible content on more than one display.

Expected:

- [ ] Raw packet stores all display recordings or composed raw output as expected.
- [ ] Final `recording.mp4` shows the virtual desktop layout.
- [ ] No display is missing.
- [ ] Mouse/click overlays map into the correct display area.
- [ ] Manifest records mode `allScreens`.
- [ ] `sourceRect` represents the union/virtual desktop metadata.

## Region Capture

This mode recently had a blank-video bug caused by unflipped Y coordinates. Test it carefully.

- [ ] Capture a region near the top of the main display.
- [ ] Capture a region near the bottom of the main display.
- [ ] Capture a region near the left edge.
- [ ] Capture a region near the right edge.
- [ ] Capture a tall narrow browser region.
- [ ] Capture a region on a secondary display.
- [ ] Repeat the last region capture via the repeat shortcut.

Expected:

- [ ] The raw video shows the selected region, not the vertically opposite strip.
- [ ] The final video shows the selected region.
- [ ] Browser content is visible; not a blank light strip.
- [ ] `raw/capture-session.json` mode is `region`.
- [ ] `capture.sourceRect` in metadata matches pointer/global coordinates for the selected region.
- [ ] Final video dimensions match the selected region after scaling/minimum constraints.
- [ ] Click bubbles land where clicked.
- [ ] Pointer events outside the selected region are kept as raw metadata but not rendered incorrectly.
- [ ] Repeat uses the same visual region.

Useful diagnostics:

```bash
PACKET="/Users/trmd/Movies/Syn/YYYY-MM-DD/region-recording-HH-MM-SS"
mkdir -p "build/diagnostics/$(basename "$PACKET")"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration,nb_frames -of json "$PACKET/raw/recording-source.mp4"
ffmpeg -hide_banner -loglevel error -y -ss 1 -i "$PACKET/raw/recording-source.mp4" -frames:v 1 "build/diagnostics/$(basename "$PACKET")/raw-001.png"
ffmpeg -hide_banner -loglevel error -y -ss 1 -i "$PACKET/recording.mp4" -frames:v 1 "build/diagnostics/$(basename "$PACKET")/final-001.png"
```

## Smart Region Capture

- [ ] Capture a smart region for 10-15 seconds.
- [ ] Move the cursor inside the selected area.
- [ ] Move the cursor near each edge of the selected area.
- [ ] Click several times.

Expected:

- [ ] Raw recording captures the full selected display.
- [ ] Manifest stores the selected smart region.
- [ ] Final video is a fixed-size crop following the cursor.
- [ ] Crop does not jump outside display bounds.
- [ ] Click bubbles render at the correct locations.
- [ ] Final crop is not blank when the cursor moves near top/bottom edges.

## Active Window Capture

Active Window means follow the currently foremost window during recording.

- [ ] Start Active Window capture with a browser foremost.
- [ ] Switch to another app during recording.
- [ ] Resize or move the frontmost window.
- [ ] Switch back to the original app.

Expected:

- [ ] Final video follows whichever window is foremost at each time.
- [ ] Canvas size is fixed by the largest observed window plus padding.
- [ ] Smaller windows are padded rather than resizing the video.
- [ ] Pointer/click overlays remain mapped.
- [ ] `raw/active-window-samples.json` exists.
- [ ] Manifest records active-window metadata.
- [ ] No blank sections when switching windows.

## Select Window Capture

Select Window means capture the specific selected window.

- [ ] Open Select Window mode.
- [ ] Verify highlight/selector UI.
- [ ] Select a non-Syn app window.
- [ ] Record 10 seconds.
- [ ] Move focus to another app during recording.
- [ ] Move/resize the selected window if possible.

Expected:

- [ ] Capture remains tied to the selected window, not the current frontmost window.
- [ ] Syn windows are not offered as capture targets.
- [ ] Selector confirm/cancel works.
- [ ] Final video shows the selected window only.
- [ ] Manifest records mode `selectedWindow`, window ID/app/title when available.

Fixtures:

```bash
./script/selector_confirm_fixture.sh selectedWindow
./script/selector_input_fixture.sh selectedWindow
./script/selector_recording_fixture.sh selectedWindow
```

## Chrome Tab Capture

- [ ] Open Chrome or Arc test browser content with a clear title.
- [ ] Open Chrome Tab mode.
- [ ] Select a tab.
- [ ] Record 10 seconds.
- [ ] Switch tabs/windows during recording.

Expected:

- [ ] Tab selector lists expected tabs.
- [ ] Selected tab/window is activated.
- [ ] Capture records the selected browser tab/window path.
- [ ] If Automation permission is needed, Syn handles the request clearly.
- [ ] Manifest records Chrome tab metadata.
- [ ] Final video is not blank.

Fixtures:

```bash
./script/live_capture_fixture.sh chromeTab --duration 2
SYN_UI_SHOW_CHROME_TAB_SELECTOR=1 ./script/capture_syn_ui.sh build/ui-captures/syn-chrome-tab-selector-current.png
```

## Recording Controls

- [ ] Start a recording.
- [ ] Pause after a few seconds.
- [ ] Wait while paused.
- [ ] Resume.
- [ ] Stop while recording.
- [ ] Repeat with Stop while paused.

Expected:

- [ ] Pause freezes elapsed time.
- [ ] Resume continues from the paused elapsed time.
- [ ] Paused time is excluded from final duration.
- [ ] Stop while recording freezes HUD timer and enters processing.
- [ ] Stop while paused closes the pause interval at the stop timestamp.
- [ ] Stop cannot be clicked repeatedly during processing.
- [ ] Pause cannot be clicked during processing.
- [ ] Packet duration matches recorded time, not wall-clock time.
- [ ] `manifest.json` and `raw/capture-session.json` contain pause intervals.

## Annotation Controls

- [ ] Start a short recording.
- [ ] Use rectangle annotation.
- [ ] Use arrow annotation.
- [ ] Use pen annotation.
- [ ] Clear annotations.
- [ ] Draw again after clearing.
- [ ] Pause, try drawing, resume.
- [ ] Stop and process.

Expected:

- [ ] HUD controls are visible and usable while recording.
- [ ] Drawing is ignored or disabled while paused if intended.
- [ ] Clear removes active annotations going forward.
- [ ] `raw/annotations.json` records strokes.
- [ ] Final `recording.mp4` burns in annotations.
- [ ] Manifest records annotation counts/mapping.
- [ ] Agent prompt mentions annotation metadata.
- [ ] Controls are disabled during processing.

## Pointer And Click Metadata

- [ ] Move mouse slowly.
- [ ] Move mouse quickly.
- [ ] Click inside the capture area.
- [ ] Click outside a region capture area.
- [ ] Click near each corner of a region/smart-region capture.

Expected:

- [ ] `raw/pointer-events.json` exists.
- [ ] Pointer event count is nonzero.
- [ ] Click events are stored as metadata.
- [ ] Click bubbles render as expanding bubbles in final video.
- [ ] In-region clicks map correctly.
- [ ] Out-of-region clicks remain raw metadata and are not rendered into the wrong location.
- [ ] Manifest reports mapped/unmapped event counts.

## Microphone And Transcription

- [ ] Record clear spoken audio.
- [ ] Record silence.
- [ ] Record while changing microphone input if available.

Expected:

- [ ] Mic meter moves when speaking.
- [ ] Raw audio source exists.
- [ ] Transcript files exist:
  - `raw/transcript.txt`
  - `raw/transcript.vtt`
  - `raw/transcript.json`
  - `transcript.md`
- [ ] Manifest provider is `local-whisper.cpp-bundled`.
- [ ] Manifest model is `ggml-base.en.bin`.
- [ ] Silence does not crash processing.
- [ ] Failed transcription creates a partial packet with useful notes.

## Processing And Performance

- [ ] Process a 10 second packet.
- [ ] Process a 60 second packet.
- [ ] Process a packet with visible changes every 2-3 seconds.
- [ ] Process a mostly static packet.

Expected:

- [ ] Packet eventually reaches succeeded or partial, not stuck forever.
- [ ] `manifest.json` contains `processing.stageTimings`.
- [ ] `agent-prompt.md` contains `## Processing Timings`.
- [ ] `processing.notes` includes a timing summary.
- [ ] Slow stages are visible, especially Claude summary and OpenAI frame planning.
- [ ] UI stays responsive during processing.
- [ ] History item shows the right status.
- [ ] Copy Prompt/Copy Packet works after processing.

Useful timing check:

```bash
jq -r '.processing.stageTimings[] | "\(.name)\t\(.durationSeconds)"' "$PACKET/manifest.json" | sort -k2 -nr
```

## Frame Extraction And Semantic Selection

- [ ] Use a recording with several distinct visual states.
- [ ] Use a recording with only one visual state.
- [ ] Use a recording with a browser and text-heavy UI.

Expected:

- [ ] `frames/candidates/metadata.json` exists.
- [ ] `frames/full/` contains selected full-resolution frames.
- [ ] `frames/compressed/` contains selected compressed frames.
- [ ] Candidate metadata includes timestamps, perceptual hashes, pixel differences, app/window context.
- [ ] Dedupe removes near-identical frames.
- [ ] OpenAI semantic planning selects meaningful frames.
- [ ] `semantic-segments.json` exists.
- [ ] `semantic-timeline.md` exists.
- [ ] Agent prompt references selected frame paths.

Optional candidate debug:

```bash
SYN_KEEP_CANDIDATE_FRAMES=1 ./script/smoke_packet_fixture.sh
```

## Packet Artifacts

For a completed packet, check:

- [ ] `recording.mp4`
- [ ] `summary.md`
- [ ] `transcript.md`
- [ ] `manifest.json`
- [ ] `agent-prompt.md`
- [ ] `agent-prompts/general-coding.md`
- [ ] `agent-prompts/implementation-plan.md`
- [ ] `agent-prompts/qa-bug-report.md`
- [ ] `frames/full/`
- [ ] `frames/compressed/`
- [ ] `frames/candidates/metadata.json`
- [ ] `raw/recording-source.mp4`
- [ ] `raw/capture-session.json`
- [ ] `raw/pointer-events.json`
- [ ] `raw/audio-source.wav`
- [ ] `raw/transcript.*`
- [ ] `semantic-segments.json`
- [ ] `semantic-timeline.md`
- [ ] Default `.zip`

Expected:

- [ ] Default zip excludes `raw/`.
- [ ] Default zip includes agent-facing prompt/summary/transcript/manifest/selected frames.
- [ ] Manifest paths match files on disk.
- [ ] Packet title and folder name are sane.
- [ ] Created date is correct.
- [ ] Duration is plausible.

## History And Packet Actions

- [ ] Select each History item.
- [ ] Open Folder.
- [ ] Copy Packet or Copy Prompt.
- [ ] Reveal Zip.
- [ ] Create Compact Zip.
- [ ] Create Raw Zip.
- [ ] Delete a disposable packet.
- [ ] Retry Processing on a partial packet.

Expected:

- [ ] Selection updates details.
- [ ] Open Folder opens the right packet folder.
- [ ] Copy action places usable handoff text on clipboard.
- [ ] Reveal Zip works only when zip exists.
- [ ] Compact zip excludes heavy/raw files.
- [ ] Raw zip includes raw recovery files.
- [ ] Delete removes the packet from history and disk after confirmation.
- [ ] Retry can process segment-only/interrupted raw packets.
- [ ] Missing zip does not show impossible actions.

## Video Editing

- [ ] Open a completed packet.
- [ ] Set trim start/end.
- [ ] Save trimmed copy.
- [ ] Try invalid start/end values.
- [ ] Try very short trim.

Expected:

- [ ] `recording-edited.mp4` is created.
- [ ] Original `recording.mp4` remains untouched.
- [ ] Manifest records edited recording path.
- [ ] Edited video duration matches trim range.
- [ ] Invalid ranges are rejected or clamped clearly.
- [ ] Compact/default/raw zip behavior around edited recording matches current contract.

## Settings And Keychain

- [ ] Open Settings.
- [ ] Save OpenAI API key.
- [ ] Save Anthropic API key.
- [ ] Overwrite each key.
- [ ] Clear each key if UI supports it.
- [ ] Relaunch Syn.

Expected:

- [ ] Key status updates after save.
- [ ] Raw key is never displayed after save.
- [ ] Relaunch preserves availability status.
- [ ] Processing uses configured providers when keys are available.
- [ ] Missing keys produce local/fallback behavior or partial status with useful notes.

## Project Context

- [ ] Set a project context folder in Settings.
- [ ] Process a safe test packet.
- [ ] Clear project context folder.
- [ ] Process another packet.

Expected:

- [ ] Packet with context includes `project-context.md`.
- [ ] Manifest records `files.projectContext`.
- [ ] Agent prompt includes `## Project Context`.
- [ ] Context snapshot includes metadata, git status, README excerpt when available.
- [ ] Context snapshot does not include secrets or heavy files.
- [ ] Packet after clearing context does not include project context.

## Failure And Recovery

- [ ] Quit Syn during or immediately after a raw recording.
- [ ] Relaunch Syn.
- [ ] Retry processing an interrupted packet.
- [ ] Temporarily remove/move an expected raw segment in a disposable packet.
- [ ] Temporarily block/misconfigure one AI key for a disposable packet.

Expected:

- [ ] Interrupted history recovery finds partial/failed raw packets.
- [ ] Retry works when enough raw material exists.
- [ ] Missing segment creates a useful failure or partial status.
- [ ] AI failure creates a partial packet, not a crash.
- [ ] Partial packets still include raw metadata and retry actions.

## Long Recording Warning

Do not wait 30 minutes manually unless needed. Use fixture coverage first.

- [ ] Run duration warning fixture through the smoke.

Expected:

- [ ] 30 minute warning threshold is covered.
- [ ] No hard recording limit is enforced.
- [ ] UI warning text is visible when threshold is crossed.

Manual long-run, only when needed:

- [ ] Record past 30 minutes.
- [ ] Confirm warning appears once.
- [ ] Continue recording after warning.
- [ ] Stop and process.

Expected:

- [ ] Recording continues after warning.
- [ ] Duration is correct.
- [ ] Processing can be retried if it fails.

## Regression Checklist

Run these after changes to capture, HUD, coordinates, hotkeys, or processing.

- [ ] Stop freezes recording timer after entering processing.
- [ ] Pause/Stop disabled during processing in HUD.
- [ ] Pause/Stop disabled during processing in Overview banner.
- [ ] Region capture near top and bottom of main display is not blank.
- [ ] Region capture on secondary display uses the selected area.
- [ ] Repeat last region uses the same visual region.
- [ ] Two-shift repeat does not beat two-shift-plus-R picker.
- [ ] Chrome tab selector still works after hotkey/picker changes.
- [ ] Active Window follows changing frontmost windows.
- [ ] Select Window does not follow unrelated frontmost windows.
- [ ] Raw packet processing timings are written.
- [ ] Default zip excludes raw files.
- [ ] Compact zip excludes heavy files.
- [ ] Raw zip includes raw files.

## Minimal Release Candidate Pass

Before calling a build test-ready:

- [ ] `./script/build_and_run.sh --verify`
- [ ] `./script/smoke_packet_fixture.sh`
- [ ] `./script/live_capture_fixture.sh screen --duration 2`
- [ ] `./script/live_capture_fixture.sh region --duration 2`
- [ ] `./script/live_capture_fixture.sh selectedWindow --duration 2`
- [ ] `./script/hotkey_fixture.sh`
- [ ] `./script/live_hotkey_fixture.sh held-r`
- [ ] Photograb Overview.
- [ ] Photograb picker.
- [ ] Photograb recording HUD.
- [ ] Manual 10 second region capture on browser content.
- [ ] Manual 10 second selected-window capture.
- [ ] Manual 10 second active-window capture with an app switch.
- [ ] Process one safe manual packet end-to-end.
- [ ] Inspect `manifest.json`, selected frames, summary, transcript, and zip.
