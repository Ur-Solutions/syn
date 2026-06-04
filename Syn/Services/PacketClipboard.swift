import AppKit
import Foundation

enum PacketClipboard {
    /// Concise, paste-ready handoff text for a coding agent. Deliberately a plain string (no file
    /// URL) so pasting into an agent yields readable instructions, not a folder reference. Points
    /// the agent at the summary first (which is written in tiers and improves over ~25-30s) and
    /// then the full agent prompt.
    static func handoffText(folderURL: URL) -> String {
        let path = folderURL.standardizedFileURL.path
        return """
        You've been handed a Syn review packet to investigate. It is located at:

        \(path)

        1. Read `\(path)/summary.md` — the review summary. It is written in tiers: a quick pass \
        appears first and is replaced by fuller ones within ~25-30 seconds (the individual tiers \
        are also saved under `\(path)/summaries/` as fast / balanced / full). If \
        `\(path)/progress.md` does not yet say "complete", the full summary isn't ready — wait \
        ~25-30 seconds and re-read `summary.md`.
        2. Read `\(path)/agent-prompt.md` for the full packet: the narrated transcript, selected \
        frames, suggested tasks, and capture metadata.

        The user's spoken narration (the transcript) is the primary description of what they want — \
        base your work on what they say, using the recording and frames as corroborating evidence.
        """
    }

    /// Copy the plain-text handoff (string only) to the clipboard.
    @discardableResult
    static func copyHandoff(folderURL: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(handoffText(folderURL: folderURL), forType: .string)
    }
}
