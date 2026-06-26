# Syn Collaboration & Integrations PRD

Date: 2026-06-12

Status: Draft

Owner: Syn

## Summary

Syn today is an excellent single-player tool: one person records narrated visual
feedback and turns it into an agent-ready packet on their own machine. This PRD
covers the next axis — getting packets *out* of one machine and *into* the places
where work actually happens: other recording tools, issue trackers, coding agents,
and eventually teammates.

It defines four features that deliberately build on one another:

1. **Import Video** — ingest any external screen recording (a Loom download, a
   Zoom clip, a QuickTime capture, a phone video of a flickering screen) and run
   it through the existing packet pipeline. Syn stops being only a recorder and
   becomes the agent-translation layer for *any* recording.
2. **Share Links** — give every packet a copyable link backed by storage the org
   already owns, plus a self-contained viewer. This is the "stop recording → link
   on clipboard → paste anywhere" experience people love about Loom, without
   depending on a third party to host the video.
3. **Linear Integration** — turn a packet (or each segment of one) into a Linear
   issue with summary, repro steps, key frames, flagged-element metadata, and a
   share link — wired so an assigned coding agent receives the full semantic
   recording, not just prose.
4. **Multiplayer / Org** — a thin index over org-owned packet storage: a team
   inbox, shared configuration, org-managed processing keys, and cross-reporter
   element clustering. Staged last; grows out of Share Links rather than replacing
   the local-first model.

The guiding principle mirrors the rest of Syn: **local-first, privacy-preserving,
opt-in.** Nothing leaves the machine unless the user sends it, storage is owned by
the user or their org rather than by Syn, and every integration follows the same
user-controlled processing rules as the existing packet pipeline.

## Why Not A Direct Loom Integration

The original ask included a Loom integration. After investigation, a direct
"Syn → Loom" integration is not buildable today:

- Loom does not offer an open API. It offers only the `loomSDK`, which embeds
  Loom's *own* recorder inside third-party web apps — it does not let an external
  app push a finished video into Loom and receive a share link.
- Even manual upload to Loom is gated to Business / Enterprise plans.

So "Syn renders a packet, uploads the video to Loom, and gets a Loom link back" is
not a viable path. The underlying user wants, however, decompose cleanly into two
things Syn *can* own end to end:

- The **import** half ("I already have a recording elsewhere") → **Import Video**.
  Loom Business/Enterprise users can download their own mp4s; everyone else has
  Zoom, QuickTime, OBS, and phone captures.
- The **share** half ("I want a link I can paste") → **Share Links** over
  org-owned storage.

If Loom (or a competitor) ships a real upload/export API later, it slots in as one
additional **share destination** under the Share Links abstraction. The
architecture below is designed so that day-one work is not wasted if that happens.

## Problem

The packet is good. The distribution is manual.

- The handoff today is "reveal the folder, copy the prompt, paste it into an
  agent, or zip and send." That works for the recorder, alone, at their desk.
- Feedback frequently originates in *other* tools. A teammate sends a Loom or a
  Zoom clip. A PM screen-records a bug on their phone. None of that can become a
  Syn packet, so all of Syn's semantic processing (transcription, OCR, frame
  selection, semantic timeline, agent prompts) is unavailable to it.
- There is no shareable artifact for humans. A packet folder or zip is great for
  an agent and awful for a colleague who just wants to watch 40 seconds and
  understand the bug.
- There is no path into the tracker. Every team already triages in an issue
  tracker; Syn output has to be re-typed into one by hand, losing the structured
  repro steps, frames, and element metadata along the way.
- Coding agents that consume issues (Linear's agent assignment, etc.) receive a
  prose description, not the rich semantic packet Syn already produced.
- Nothing is shared across people. Element identity is stable across machines
  (selector, test id, component name, source location), but there is no place
  where "three people flagged `ExportButton` this week" can be observed.

## Product Goals

1. Ingest an arbitrary external video file and produce a valid packet from it,
   degraded gracefully where native capture metadata is unavailable.
2. Give every packet (recorded or imported) an optional copyable share link backed
   by storage the user or org controls.
3. Ship a self-contained, server-free packet viewer suitable for human review.
4. Create a Linear issue from a packet in one action, with summary, repro steps,
   frames, flagged-element metadata, and a share link.
5. Split a multi-issue recording into a parent issue plus sub-issues, one per
   semantic segment, when the user chooses.
6. Make Syn-created issues *agent-ready*: an assigned coding agent can reach the
   full packet, not just the issue body.
7. Provide a "verify fix" loop: re-record the remembered capture target and attach
   a before/after comparison to the originating issue.
8. Lay the multiplayer foundation as a thin index over org-owned storage — team
   inbox, shared config, org-managed keys, element clustering — without forcing a
   centralized SaaS that holds customer video.
9. Keep every feature optional and off by default. Syn must remain fully usable
   with no account, no network destination, and no tracker connected.

## Non-Goals

1. Do not build a Syn-hosted video service. Syn does not store customer recordings
   on Syn-operated infrastructure. Storage is the user's bucket or the org's.
2. Do not require a Loom account, Loom plan, or Loom SDK for any feature.
3. Do not make import depend on reverse-engineering any third party's private API.
4. Do not require a Linear account to use Syn. Linear is one optional destination.
5. Do not block packet generation if a share upload or issue creation fails — those
   are post-packet actions and must degrade to "packet is still on disk."
6. Do not send packet contents to any external service (storage, tracker, agent)
   without an explicit user action per packet or an explicit standing opt-in.
7. Do not, in the MVP, build real-time co-editing, presence, or comment threads.
   "Multiplayer" here means shared storage + index + triage, not live collaboration.
8. Do not invent a new auth system. Reuse the existing Keychain-backed `SecretStore`
   for tokens and credentials, exactly as API keys are stored today.

## User Stories

### Importing An External Recording

As a developer who was sent a Loom of a bug, I download the mp4, drop it onto Syn,
and Syn produces a packet: transcript from the video's audio, OCR'd frames, a
semantic timeline, an auto-summary, and agent prompts — the same artifacts I'd get
from a native Syn recording, minus the pointer/element data that only live capture
can produce.

### Sharing A Packet As A Link

As someone who just recorded feedback, I click "Copy share link." Syn uploads the
packet (or a viewer-friendly subset) to my configured bucket and puts a link on my
clipboard. I paste it into Slack; my teammate opens it in a browser, watches the
clip, reads the transcript, and sees the flagged elements — no Syn install, no app.

### Filing A Linear Issue

As a developer, after recording a bug I click "Create Linear issue." Syn opens a
short confirmation with a pre-filled title, body (expected/actual + repro steps),
chosen team/project/labels, attached key frames, and the share link. I confirm and
the issue exists, linked back to the packet.

### Splitting One Recording Into Many Issues

As a QA tester, I record a ten-minute pass that surfaces four separate problems.
Syn's semantic timeline already segmented the recording. I choose "Create issues
per segment" and get a parent issue with four sub-issues, each carrying its own
clip range, frames, and narration excerpt.

### Handing An Issue To A Coding Agent

As a team using agent assignment in Linear, when we assign a Syn-created issue to a
coding agent, the agent can fetch the underlying packet (transcript, frames,
flagged elements with source locations) via the issue's packet reference, and acts
on the real recording instead of a paraphrase.

### Verifying A Fix

As the original reporter, when a Syn-created issue moves to In Review, Syn offers to
re-record the remembered capture target (window/region/tab) and the flagged
elements. It attaches a before/after comparison to the issue, so the ticket closes
with visual proof.

### Triaging As A Team

As a tech lead, I open the Syn team inbox and see packets my teammates recorded
this week — including non-engineers who installed Syn only to report bugs. I triage,
assign, and convert the good ones into Linear issues. Syn highlights that three of
them flagged the same `ExportButton` component.

## Feature 1: Import Video

### Overview

Import takes an external media file and runs it through the existing
`PacketProcessor` pipeline, producing a normal packet under
`~/Movies/Syn/<day>/<slug>-<timestamp>/` with a standard `manifest.json`. The
packet is marked as imported so consumers know which metadata is absent.

### Entry Points

- **Drag and drop** a video file onto the main window or the menu bar icon.
- **Menu bar / app command:** "Import Video…" with a file picker.
- **`Open With → Syn`** registered for common video UTIs.
- **Shortcut** (proposed, non-conflicting): `Command + Shift + I`.

Accepted inputs: `.mp4`, `.mov`, `.m4v`, and other AVFoundation-decodable
containers. If audio is in a separate file, allow an optional "import with separate
audio track" path.

### Pipeline Reuse

An imported file is treated as the equivalent of the merged raw recording. The
existing critical path applies directly:

- Transcription runs on the file's audio track via the bundled whisper-cli
  (offline path; the streaming-during-recording path does not apply to import).
- Frame extraction + Vision OCR run on the decoded video.
- Instant visual-change frame selection, then optional semantic frame planning.
- Auto-summary tiers via `AIProviderService`, exactly as today.
- `manifest.json`, `agent-prompt.md`, and `agent-prompts/` are written by the same
  code paths.

### Degraded Metadata

Imported packets cannot have data that only live capture produces. The manifest
must represent this honestly rather than emitting zeros that read as real:

- `pointerEvents`, `pointerMapping`, click bubbles → **absent**, not empty. UI must
  not imply clicks were captured.
- Flagged elements / element intelligence → **absent** (no live picker ran).
- Active-window samples, dynamic crop framing → **absent**.
- `capture` source metadata (app bundle, window title, Chrome tab/URL) → **unknown**
  unless derivable; record provenance instead (original filename, source label).

### Manifest Changes

Extend `PacketManifest` (bump `schemaVersion`):

```swift
struct ImportProvenance: Codable {
    var origin: String          // "import"
    var sourceKind: String?     // "loom" | "zoom" | "quicktime" | "obs" | "unknown"
    var originalFilename: String?
    var importedAt: Date
    var hasLiveCaptureMetadata: Bool   // false for imports
}
```

Add `var importProvenance: ImportProvenance?` to `PacketManifest` (nil for native
recordings). `sourceKind` is a best-effort guess from filename/container hints and
is purely informational. Agent prompts should include a short note when
`hasLiveCaptureMetadata == false` so the agent does not assume pointer/element data
exists.

### Source-Kind Hints (Best Effort, Optional)

Cheap, local heuristics only — never network calls to the source service:

- Loom downloads often carry recognizable filename patterns; tag `sourceKind`
  accordingly purely for display.
- If a sidecar transcript/caption file (`.vtt`/`.srt`) accompanies the video, offer
  to use it instead of re-transcribing.

### Open Questions (Import)

- Very long imports (multi-hour) exceed the interactive latency model. Cap with a
  warning, or background-process with progress? (Lean: background + progress, reuse
  the existing async zip/summary status pattern.)
- Should import support audio-only files (a voice memo describing a bug with no
  video)? Possible later; out of MVP.

## Feature 2: Share Links

### Overview

A share link makes a packet viewable by anyone with the URL, using storage the user
or org controls. Syn uploads a viewer-friendly subset (or the whole packet) and
returns a copyable link. Syn never hosts the bytes.

### Storage Backends (Pluggable)

Define a `ShareDestination` abstraction so backends are interchangeable:

```swift
protocol ShareDestination {
    var id: String { get }            // "s3" | "gcs" | "local-folder" | future
    var displayName: String { get }
    func upload(_ packet: PacketUploadBundle) async throws -> ShareResult
}

struct ShareResult {
    let url: URL
    let expiresAt: Date?
}
```

MVP backends:

- **S3 / GCS via presigned upload** using credentials in `SecretStore` (same
  Keychain pattern as the OpenAI/Anthropic keys). Bucket + prefix configured in
  Settings.
- **Local/shared-folder** destination (e.g. a synced Dropbox/Drive/NAS path):
  copies the bundle and produces a `file://` or known-base-URL link. Zero cloud
  setup; useful for proving the flow and for privacy-strict teams.

Future destinations slot in without changing callers: a Syn-operated relay (opt-in),
or a real Loom/third-party export API if one ships.

### The Viewer

Ship a self-contained `viewer.html` inside every packet (also usable offline from
the folder/zip, independent of sharing):

- Plays `recording.mp4` with a clickable timeline.
- Shows the transcript synced to playback (jump-to-timestamp).
- Lists semantic segments as chapters.
- Lists flagged elements; selecting one highlights its region on the current frame
  and seeks to its timestamp.
- Renders the summary and the expected/actual block.
- No server, no build step, no external requests — a single HTML file plus the
  packet's existing assets. The packet becomes shareable to *humans*, not only
  agents.

This viewer is valuable on its own (offline review) and is the payload for a
sharable link. Build it even if share upload ships later.

### Privacy & Expiry

- Sharing is always an explicit per-packet action (or an explicit standing opt-in
  per destination), never automatic.
- Default to presigned URLs with an expiry where the backend supports it; surface
  the expiry in the UI.
- A "redacted share" mode can exclude `raw/`, OCR text, or flagged-element props
  per the existing redaction posture.
- Provide "revoke / delete shared copy" where the backend allows it.

### Settings

- Configure one or more share destinations (type, bucket/path, prefix, credentials
  reference, default expiry).
- Choose a default destination; "Copy share link" uses it. Hold a modifier to pick
  a destination explicitly.

## Feature 3: Linear Integration

### Why Linear Is The Strongest Near-Term Integration

Unlike Loom, Linear has a complete, documented GraphQL API: OAuth, issue creation,
attachments, labels, sub-issues, and a maturing agent-assignment surface. It is the
team-facing destination that makes the earlier brainstorm items (repro-steps
synthesis, segmentation, verify-fix) pay off, and it is shovel-ready.

### Auth

- OAuth (preferred) or personal API token, stored in `SecretStore` exactly like the
  existing provider keys (Keychain, service `"Syn"`, dedicated account).
- On connect, fetch and cache the user's teams, projects, and labels for the
  Settings pickers.

### Packet → Issue

One action ("Create Linear issue") from packet detail and the menu bar. Pre-filled
from packet artifacts:

- **Title:** from the auto-summary's headline.
- **Description (Markdown):**
  - **Expected / Actual / Severity** block (see structured summary below).
  - **Repro steps:** synthesized from clicks + flagged elements + transcript, e.g.
    "1. Clicked *Export* (button, `SettingsView`) — 2. Dialog opened — 3. Narration:
    'this is the wrong default path'." Imported packets omit pointer-derived steps
    and fall back to transcript-derived steps.
  - **Flagged elements:** a structured section (role, label, selector/test id,
    component name, source `file:line`) an agent can parse directly.
  - **Share link** to the viewer (if Share Links is configured), plus a **packet
    reference** (see agent dispatch).
- **Attachments:** key frames (selected frames) uploaded as issue attachments;
  optionally the clip itself or its share link.
- **Metadata:** team, project, labels, and an optional issue template, from
  Settings defaults; overridable in the confirmation step.

### Structured Summary (Shared With The Prompt Pipeline)

To make issues (and agent prompts) consistently good, nudge the summary model to
emit a structured block in addition to prose:

```json
{
  "title": "Export uses wrong default path",
  "expected": "Export dialog defaults to the last-used folder",
  "actual": "Export dialog defaults to ~/Documents every time",
  "severity": "medium",
  "area": "Settings / Export"
}
```

This is a small, cheap change to the summary prompt in `AIProviderService` and
improves both the Linear body and the agent prompt. It is independently useful and
should land regardless of which integrations follow.

### Segmentation → Sub-Issues

When a recording has multiple semantic segments and the user chooses "Create issues
per segment":

- Create a **parent issue** summarizing the session.
- Create one **sub-issue per segment**, each with its own clip range (deep-link into
  the viewer at `?t=start`), segment frames, and narration excerpt.
- Link all sub-issues to the same packet reference.

### Agent Dispatch (The Payoff)

Linear increasingly supports assigning issues to coding agents. A prose description
underuses what Syn produced. So a Syn-created issue carries a **packet reference**
that an agent can resolve to the full semantic packet:

- If Share Links is configured: a stable URL to the packet bundle (manifest +
  transcript + frames + elements).
- If the Syn MCP server exists (see Cross-Cutting): a `syn://packet/<id>` reference
  the agent resolves locally for the freshest, highest-resolution artifacts.

The result is the loop: **record → issue → agent → PR**, with Syn as the evidence
layer the agent reads from, not a lossy text summary.

### Verify-Fix Loop

- When a Syn-created issue transitions to In Review / Done (polled, or via webhook
  if an org relay exists), Syn offers to **re-record the remembered capture target**
  (the `CaptureRequest` and flagged elements are already persisted per packet).
- Syn renders a **before/after** comparison — same region/element, side-by-side
  frames — and attaches it to the issue as a comment.
- The ticket closes with visual proof, and Syn graduates from a reporting tool into
  a QA loop.

### Settings (Linear)

- Connect/disconnect account.
- Default team, project, labels, issue template.
- Default behavior: single issue vs. per-segment.
- Whether to attach frames, the clip, and/or only the share link.
- Whether to enable verify-fix prompts (requires status polling/webhook).

## Feature 4: Multiplayer / Org (Future)

### Position

This is intentionally last and intentionally thin. The tension to respect: Syn is
local-first with a careful privacy posture (Keychain secrets, redaction, opt-in
everything). Multiplayer implies a server, which is where that posture usually dies.
The resolution is to make the org layer a **thin index over org-owned storage**,
not a SaaS that holds customer video. Most of "multiplayer" is already delivered by
Share Links; the rest is an index and some shared configuration.

### Staging

1. **Share links (already above).** Packets in the org's bucket, viewable by URL.
   No accounts, no server logic. This alone covers the majority of "let my
   teammates see my recordings."
2. **Team inbox.** A lightweight index service over those packets: list, filter,
   triage, assign, and link to Linear issues. The index stores **metadata and
   pointers** (title, summary, reporter, timestamps, element identities, storage
   URL), not the video bytes. A **record-only / report-only mode** lets non-engineers
   (PMs, designers, support) install Syn purely to capture and submit — they find
   the bugs and rarely file good reports today.
3. **Org configuration distribution.** Shared prompt profiles, redaction policies,
   default Linear team/project, project-context mappings, and **org-managed
   processing keys** (so individuals don't each need their own OpenAI/Anthropic key
   — quietly one of the biggest adoption blockers). Distributed via a checked-in
   config file or the org service.
4. **Cross-reporter element clustering.** The unique payoff. Element identity
   (selector, test id, component name, source location) is stable across machines,
   so the org index can detect "three people flagged `ExportButton` this week" and
   merge them into one cluster with three narrations. No other tool can do this,
   because no other tool has element-level packets.

### Auth & Hosting Options (To Be Decided)

- Org SSO (Google Workspace / Okta) gating access to the index and bucket.
- Self-hostable index (single binary + the org's bucket) for privacy-strict teams,
  with an optional Syn-operated managed index for convenience. Either way, video
  bytes live in the org's storage, not Syn's.

### Explicitly Out Of Scope For Now

Live presence, real-time co-editing, threaded comments, notifications fan-out, and
billing. These come only if the index proves itself.

## Cross-Cutting: Packet Reference & MCP Server

Several features above (agent dispatch, verify-fix, team inbox, MCP-based handoff)
need a **stable packet identity and a way to resolve it to artifacts**. Define this
once:

- Every packet has a stable `packetID` (already present on `RawCaptureSession`).
  Promote it to a first-class manifest field and use it as the reference key.
- A **packet reference** is either a share URL (remote) or a `syn://packet/<id>`
  URI (local, resolved by a Syn-local MCP server / URL handler).
- A future **Syn MCP server** exposes read tools (`get_packet`, `get_transcript`,
  `get_flagged_elements`, `get_frame(t)`, `search_packets`) so any agent can *pull*
  exactly what it needs. This is out of scope to fully build here but the reference
  design must not preclude it — Linear agent dispatch is its first real consumer.

## Technical Architecture

### New / Changed Components

- `ImportCoordinator` — accepts a file URL, validates the container, stages it as a
  pseudo-raw recording, and invokes `PacketProcessor` with an `importProvenance`.
- `ShareService` + `ShareDestination` implementations (`S3ShareDestination`,
  `GCSShareDestination`, `FolderShareDestination`) — build the upload bundle and
  return a `ShareResult`.
- `PacketViewerBuilder` — emits `viewer.html` into the packet from the manifest and
  assets.
- `LinearService` — OAuth/token, GraphQL client, issue/sub-issue creation,
  attachment upload, status polling.
- `IssueComposer` — maps a packet (+ segments) to issue payload(s): title, body,
  repro steps, structured summary, attachments, packet reference.
- Manifest: add `importProvenance`, promote `packetID`, add `share` block
  (destination, url, expiry) and `linkedIssues` (tracker, id, url). Bump
  `schemaVersion`.

### Reused Components

- `PacketProcessor`, `TranscriptionService`, `FrameExtractor`, OCR, frame planning,
  `AIProviderService`, `ZipService` — all reused unchanged by Import.
- `SecretStore` — stores Linear tokens and storage credentials with the existing
  Keychain pattern.
- `AppPreferencesStore` — gains share/Linear defaults alongside the existing
  `defaultPromptProfile` and `projectContextFolderPath`.
- `CaptureRequest` persistence — already records the capture target; reused by
  verify-fix to re-record.

### Failure Posture

Every networked action is **post-packet** and must fail soft: the packet always
remains complete on disk. Upload failure → "saved locally, link unavailable, retry."
Issue creation failure → "packet ready, issue not created, retry." Mirror the
existing async `zipStatus` / `summaryStatus` pattern in the manifest with
`shareStatus` and per-issue status.

## Privacy & Security

### Default Position

- All four features are opt-in and off until configured. Syn with nothing connected
  behaves exactly as today.
- No packet content crosses the network without an explicit per-packet action or an
  explicit standing per-destination opt-in.
- Credentials (storage keys, Linear tokens) live only in `SecretStore` (Keychain),
  never in the packet, manifest, or logs.

### Sharing Risks

- A share link is a capability URL: anyone with it can view. Default to expiring
  presigned URLs; surface expiry; offer revoke/delete where supported.
- Redacted-share mode can drop `raw/`, OCR text, and element props before upload.
- The viewer makes no external requests, so opening a shared packet leaks nothing
  to Syn.

### Tracker Risks

- Issue bodies and attachments may contain sensitive screen content. Reuse existing
  redaction controls before attaching frames; let the user review the composed issue
  before it is created.

### Org Risks (Future)

- The index stores metadata + pointers, not video. Access is gated by org SSO.
- Org-managed processing keys must be scoped and rotatable; per-user override stays
  available.

## MVP Scope

### MVP A: Import Video

- Drag-drop + file picker import of common video containers.
- Full pipeline reuse; `importProvenance` in the manifest; honest "no live
  metadata" representation in UI and agent prompt.
- Background processing with progress for long imports.

### MVP B: Viewer + Share (Folder Backend First)

- `viewer.html` in every packet (works offline).
- `FolderShareDestination` (synced/NAS folder) → copyable link. Proves the flow
  with zero cloud setup.
- S3/GCS presigned backend as the immediate follow-on.

### MVP C: Linear — Single Issue

- Connect account; default team/project/labels in Settings.
- Packet → single issue with structured summary, repro steps, frames, share link.
- Structured summary block added to the summary pipeline (independently useful).

### MVP D: Linear — Segmentation, Agent Dispatch, Verify-Fix

- Per-segment sub-issues.
- Packet reference on issues for agent dispatch.
- Verify-fix re-record + before/after attachment.

### Recommended Build Order

1. Structured summary block (cheap, improves everything downstream).
2. Viewer + Folder share (high value, no external dependencies).
3. Import Video (strategic reach; reuses the whole pipeline).
4. Linear single issue → S3/GCS share → segmentation → agent dispatch → verify-fix.
5. Multiplayer/org index, once packet volume across people justifies it.

Rationale: 1–2 ship value with no third-party auth and de-risk the data shapes
(structured summary, packet reference, viewer) that every later feature depends on.
Import is independent and high-leverage. Linear is sequenced after the share link
exists so issues can carry a real, viewable artifact from day one.

## Future Scope

- Syn MCP server (full pull-based agent access) — sketched in Cross-Cutting.
- Additional trackers: GitHub Issues, Jira (same `IssueComposer` abstraction).
- Additional share destinations, including a third-party export API (e.g. Loom) if
  one ships.
- Console/network capture via the web bridge, attached to issues as diagnostic
  evidence.
- Audio-only import.

## Open Questions

1. Default share expiry, and whether redacted-share should be the default rather
   than opt-in for org contexts.
2. Linear status sync: polling vs. requiring an org relay/webhook for verify-fix.
3. Where the per-segment clip lives for sub-issues: deep-link into one viewer
   (`?t=`) vs. rendered per-segment clips (heavier, more portable).
4. Org index hosting: self-host-first, managed-first, or both from the start.
5. Whether org-managed processing keys proxy through an org service or are
   distributed to clients (security vs. simplicity trade-off).

## Risks

### Loom Expectation Mismatch

Users may expect a literal Loom integration. Mitigation: frame Import + Share as
"works with your Loom downloads and gives you your own links," and document the API
limitation plainly.

### Share Security

Capability URLs can leak. Mitigation: expiry by default, revoke support, redacted
mode, and clear UI about who can see a link.

### Linear API Surface Drift

GraphQL schema and agent-assignment APIs evolve. Mitigation: isolate in
`LinearService`; pin and test against the documented schema; degrade gracefully.

### Scope Creep Into SaaS

"Multiplayer" can balloon into a hosted product. Mitigation: hard non-goals (no
Syn-hosted video, index stores pointers not bytes), and stage strictly behind
Share Links.

### Imported-Packet Misrepresentation

An imported packet that silently looks like a native one would mislead agents.
Mitigation: `hasLiveCaptureMetadata = false`, explicit absence (not zeros), and a
prompt note.

## Testing Plan

### Import

- Import mp4/mov/m4v fixtures → valid packet with `importProvenance`, no fabricated
  pointer/element data, transcript + frames + summary present.
- Sidecar `.srt`/`.vtt` honored when offered.
- Long-import background path reports progress and completes.

### Viewer

- `viewer.html` opens offline, plays the clip, syncs transcript, lists segments and
  flagged elements, makes zero network requests (verify via a request monitor).

### Share

- Folder backend produces a working link to a viewable bundle.
- S3/GCS presigned upload round-trips; expiry honored; revoke works where supported.
- Upload failure leaves the packet intact and reports retryable status.

### Linear

- Single-issue creation: title/body/labels/attachments/share link correct against a
  recorded fixture; review-before-create respected.
- Per-segment sub-issues created and linked to one packet reference.
- Agent dispatch: packet reference resolves to artifacts.
- Verify-fix: re-record uses the persisted `CaptureRequest`; before/after attaches.
- Auth failure and API error paths degrade without losing the packet.

### Manifest

- New fields (`importProvenance`, promoted `packetID`, `share`, `linkedIssues`)
  encode/decode; `schemaVersion` bump handled; older packets still load.

## Implementation Milestones

### Milestone 1: Structured Summary + Manifest Shapes

Add the structured expected/actual/severity block to the summary pipeline; promote
`packetID`; define `importProvenance`, `share`, and `linkedIssues`; bump schema.

### Milestone 2: Packet Viewer

`PacketViewerBuilder` emits `viewer.html`; wire into the normal packet write path;
offline tests.

### Milestone 3: Share Service (Folder, then S3/GCS)

`ShareDestination` abstraction + Folder backend + "Copy share link"; then presigned
S3/GCS using `SecretStore` credentials; `shareStatus` in the manifest.

### Milestone 4: Import Video

`ImportCoordinator`, entry points, pipeline reuse, degraded-metadata handling,
background progress.

### Milestone 5: Linear Single Issue

`LinearService` + `IssueComposer`; Settings; review-before-create; attachments +
share link.

### Milestone 6: Linear Segmentation, Agent Dispatch, Verify-Fix

Sub-issues; packet reference for agents; verify-fix re-record + before/after.

### Milestone 7: Org Index (Future)

Team inbox over org storage; report-only mode; shared config + org keys; element
clustering.

## Success Metrics

- Time from "I have a recording" (native or imported) to "a teammate/agent has it"
  drops to a single action.
- Share of packets that become a tracked issue without manual re-typing.
- Imported-video packets produce usable agent prompts (qualitative review).
- Verify-fix loop used on a meaningful fraction of Syn-created issues.
- (Org) number of distinct reporters per repo; element clusters surfaced.

## Recommended First Build

Ship **the structured summary block + the offline `viewer.html` + the Folder share
backend** first. It has no third-party auth, no cloud setup, and no API risk; it
immediately makes packets shareable to humans; and it locks down the three data
shapes (structured summary, packet reference, viewer) that Import and Linear both
depend on. Import Video follows as the highest-leverage independent feature, then
Linear in the order above.
