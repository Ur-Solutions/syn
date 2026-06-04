# Syn Specification Corroboration

Source spec: `/Users/trmd/Atlas/vault/00 Tormod/Syn.md`

Date: 2026-06-04

This document records the specification decisions made before implementation. Each answer reflects the accepted direction after discussion.

## Core Product

1. **Is the MVP a recording tool or an agent-ready feedback package generator?**
   Answer: It is an agent-ready feedback package generator. The MVP must record screen and microphone input, then generate transcript, summary, frame slices, packet folder, zip, and clipboard-ready agent prompt.

2. **Should MVP support all initially listed capture modes?**
   Answer: MVP supports screen, all-screens, Chrome tab, active-window-follow, selected window, and drawable region. Smart Region is a broader/full-spec mode from the v2 ideation list; it is useful, implemented, and verified, but it should be discussed separately from the narrower MVP promise.

3. **Should Syn be a menu bar utility or normal Dock app?**
   Answer: Menu bar utility first, with global hotkeys and a small settings/history window.

4. **What is the recording lifecycle?**
   Answer: Hotkey opens picker or repeats last capture, user selects/starts capture, HUD appears, user records with mic narration, user pauses/resumes or stops, Syn processes, creates the packet, copies the agent prompt plus packet folder file URL, reveals output, and makes a zip available.

5. **How many shortcuts are needed?**
   Answer: Two global shortcuts: `Left Shift + Right Shift + R` always opens the picker, and `Left Shift + Right Shift` repeats the last capture mode after both Shift keys are released without another key participating. If no recording has completed yet, both open the picker. Because the repeat chord is a prefix of the picker chord, repeat should wait through about a one-second suffix grace plus input-drain pass so a same-gesture `R` can still cancel pending repeat and open the picker, while late unrelated `R` key presses do not steal an already-resolved repeat. The hotkey listener should use a listen-only HID event tap plus supplemental session/annotated-session/AppKit R-key monitoring, derive left/right Shift state from macOS event modifier bits when available, sample/poll the R key while the chord is armed, keep polling during the pending-repeat grace window, and remember any R participation in the current chord lifecycle.

6. **What should repeat capture remember?**
   Answer: It remembers the last capture mode and enough target data to retry safely. Screen remembers display, Chrome tab remembers the selected tab metadata and reactivates that tab when possible, region and Smart Region remember display-relative rectangles, active-window-follow uses the current frontmost window dynamically, and selected-window retries only if the selected window can be resolved.

## Capture Modes

7. **What does active window mode mean?**
   Answer: Active-window-follow records whichever window is currently foremost, and changes automatically as focus changes during recording.

8. **Do we also need selected-window mode?**
   Answer: Yes. Selected-window mode records one explicitly chosen window even if focus changes.

8a. **What does Chrome tab mode mean?**
    Answer: Chrome Tab lists readable Google Chrome tabs through macOS Automation, lets the user choose one, activates that tab, then records the activated Chrome window while storing tab metadata such as title, URL, window index, tab index, and resolved window ID.

9. **How should active-window-follow output handle changing window sizes?**
   Answer: The final video uses a fixed canvas computed after recording. The largest captured active-window bounds set the size, then 24 px padding is added on all sides. Smaller windows are centered. Padding uses a neutral MVP background, with styled backgrounds later.

10. **Should window capture include frame/title bar/shadow?**
    Answer: Yes, include the full visible window frame, title bar, toolbar, and shadow where macOS capture APIs allow it.

11. **How should drawable region selection work?**
    Answer: A translucent overlay spans displays, the user drags a rectangle, dimensions are shown, the selected rectangle can be dragged to refine placement before confirmation, and recording starts only after confirm.

11a. **How should Smart Region work?**
    Answer: The user chooses an initial rectangle with the same region selector. Syn records the full selected display as raw source material, stores the selected rectangle as `capture.smartRegion`, then renders `recording.mp4` as a fixed-size crop that follows cursor movement through the source display. The raw full-display capture remains under `raw/` for recovery/debugging.

12. **How should selected-window selection work?**
    Answer: Click-to-select on screen with eligible window highlighting and confirmation. A window list can come later.

13. **Should cursor movement be recorded?**
    Answer: Yes. The cursor must be visible in the video.

14. **Should clicks be shown?**
    Answer: Yes. Clicks should be burned into the final video as expanding bubbles.

15. **Should pointer/click metadata be stored?**
    Answer: Yes. Store cursor movement and click events with timestamps and coordinates.

16. **Which pointer coordinate spaces should be stored?**
    Answer: Store both source coordinates and final video canvas coordinates, plus transform metadata.

17. **Should pointer metadata be captured in all modes?**
    Answer: Yes. Events outside the captured output are kept as raw metadata when available, but not rendered into the final video.

## Audio, Video, Pause

18. **Should MVP record microphone or system audio?**
    Answer: Microphone only. System/app audio is deferred.

19. **Should HUD include pause/resume?**
    Answer: Yes. HUD includes timer, mic level, mode indicator, pause/resume, and stop. It stays out of the captured output and must not become the active captured window.

20. **What happens during pause?**
    Answer: Pause omits both video and mic from the final timeline. Pause intervals are recorded in `manifest.json` for debugging/history.

21. **What recording length should MVP target?**
    Answer: Optimize for 2-20 minute recordings. Warn at 30 minutes. No hard limit.

22. **What output video quality should MVP use?**
    Answer: 30 FPS H.264 MP4, prioritizing readable screen text.

23. **Should `recording.mp4` be raw or processed?**
    Answer: `recording.mp4` is the processed final video with padding and click bubbles.

24. **Should raw recordings be kept?**
    Answer: Yes. Store raw source material inside `raw/` in the packet folder.

25. **Should the default zip include raw sources?**
    Answer: No. The packet folder keeps `raw/`, but the default zip excludes `raw/`.

25a. **Should users be able to create a zip that includes raw sources?**
    Answer: Yes. Keep the normal shareable zip raw-free by default, and provide a separate on-demand raw-inclusive sibling zip for recovery/debugging handoff.

## Local Processing And AI

26. **How should transcription work?**
    Answer: Transcription is local using bundled Whisper support. Raw audio/video does not need to leave the machine.

27. **How should Whisper be packaged?**
    Answer: Bundle local Whisper support and a default model inside the app. Do not require Homebrew, Python, or an external CLI for MVP.

28. **Which AI providers are used?**
    Answer: Use provider abstraction in code. MVP exposes local Whisper for transcription, OpenAI for semantic segmentation/frame planning, and Claude Opus for final summary.

29. **What gets sent to Claude?**
    Answer: Transcript plus selected compressed/downscaled images. Raw audio/video does not need to be sent.

30. **How should image extraction work?**
    Answer: Hybrid context-aware extraction. Sample candidate frames every 2-3 seconds, pixel-dedupe visually similar frames, run local OCR over sampled frames where available, use transcript plus visual-change metadata to identify semantic topic shifts, then select useful frames around those shifts.

31. **Should the semantic frame selector inspect screenshots?**
    Answer: No for MVP image pixels. It uses timestamped transcript plus visual-change metadata, including locally recognized OCR text. Only final selected images go to the summary model.

32. **What visual-change metadata is needed?**
    Answer: Pixel diff, perceptual hash, active app/window title, capture bounds, and locally recognized OCR text with confidence/bounding-box observations when available.

33. **Should frames be full-resolution or downscaled?**
    Answer: Both. Processing emits full-resolution selected frames and compressed/downscaled LLM-ready frames.

34. **How should frame folders be organized?**
    Answer: Use `frames/full/`, `frames/compressed/`, and `frames/candidates/metadata.json`. Candidate images are not kept by default unless debug mode is enabled.

## Packet Structure

35. **What should the final packet contain?**
    Answer:
    - `recording.mp4`
    - `transcript.md`
    - `summary.md`
    - `agent-prompt.md`
    - `manifest.json`
    - `frames/full/`
    - `frames/compressed/`
    - `frames/candidates/metadata.json`
    - `raw/`
    - default zip excluding `raw/`

36. **What should be copied to the clipboard?**
    Answer: Copy the full contents of `agent-prompt.md` as plain text and the packet folder as a pasteboard file URL so the handoff works for both agents and file-oriented macOS consumers.

37. **What paths should `agent-prompt.md` reference?**
    Answer: Reference both the packet folder and the zip path, with the folder as primary.

38. **Where should packets be stored?**
    Answer: `~/Movies/Syn/YYYY-MM-DD/<slug>-<timestamp>/`, with `<slug>-<timestamp>.zip` alongside the folder.

38a. **How should users reopen packet output locations?**
    Answer: Processing reveals the packet folder automatically. The app also exposes packet-location commands: open packet folder, copy packet handoff, and reveal packet zip from the app command menu and menu bar item.

39. **What should `summary.md` look like?**
    Answer: Action-oriented for coding agents: brief overview, prioritized feedback/issues, timestamped observations, frame references, suggested implementation tasks, open questions, and explicit uncertainty where relevant.

40. **How many agent prompt variants are needed?**
    Answer: Multiple built-in prompt profiles are supported. Keep `agent-prompt.md` as the selected/default handoff prompt for clipboard compatibility, and also write the available profile variants under `agent-prompts/`.

## App UX, Permissions, Storage

41. **Should Syn keep local recording history?**
    Answer: Yes. The small window includes recent packets, processing status, duration, created time, open folder, copy packet, reveal zip, and delete.

42. **What happens if postprocessing fails?**
    Answer: Keep the raw recording, create a partial packet, mark history as failed/partial, and allow retrying stages such as transcription, frame extraction, AI summary, and zip/prompt creation.

43. **How should macOS permissions work?**
    Answer: First launch shows a setup/checklist for Screen Recording, Microphone, and Accessibility if needed. Syn verifies permissions before recording and opens System Settings when permissions are missing.

44. **How should API keys be stored?**
    Answer: Store provider keys in macOS Keychain. Do not store keys in preferences or manifests.

45. **What should the capture picker show?**
    Answer: The MVP picker needs six choices: Screen, All Screens, Chrome Tab, Active Window, Select Window, and Region. The current broader-spec picker shows those six plus Smart Region. It also shows mic status, last mode, and a settings entry.

46. **What project form should implementation start with?**
    Answer: Xcode project plus SwiftUI app with narrow AppKit interop. Menu bar behavior, hotkeys, permissions, ScreenCaptureKit, floating HUD windows, and Keychain are better handled in a normal macOS app project than a pure package scaffold.

## Post-MVP / Broader-Spec Ideas

- Automatic partitioning of the video into useful semantic segments: implemented as transcript/visual-change/OCR based frame planning plus packet artifacts `semantic-segments.json` and `semantic-timeline.md`, both referenced from `manifest.json`, the default zip, and `agent-prompt.md`.
- Drawing on screen with rectangles, arrows, and pen strokes: implemented and verified.
- Draggable region refinement: implemented and verified.
- Smart Region that follows the user/cursor: implemented and verified as a cursor-following crop from a full-display raw recording.
- Simple video editing after creation: implemented as a non-destructive trim tool that writes `recording-edited.mp4` next to `recording.mp4` and records the edited output path in `manifest.json`.
- Compact packet option: implemented as a sibling `-compact.zip` that keeps agent-facing text, manifest metadata, prompt profiles, candidate metadata, and compressed frames while excluding raw sources, full-resolution frames, and video payloads.
- Codebase connection / project setup and deeper understanding: implemented as an optional Settings-selected project folder that writes a bounded `project-context.md` metadata snapshot into each processed packet and references it from `agent-prompt.md` / `manifest.json`. The snapshot includes root path, detected project marker files, git branch/commit/status/recent commits when available, top-level structure excluding common secret/heavy folders, and a README excerpt. It does not embed source files or secret-like files.

## Deferred

- System/app audio.
