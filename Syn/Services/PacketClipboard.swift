import AppKit
import Foundation

enum PacketClipboard {
    static func copyPacket(prompt: String, folderURL: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .fileURL], owner: nil)

        let wrotePrompt = pasteboard.setString(prompt, forType: .string)
        let wroteFolder = pasteboard.setString(folderURL.standardizedFileURL.absoluteString, forType: .fileURL)
        return wrotePrompt && wroteFolder
    }

    static var copiedFolderURL: URL? {
        guard let raw = NSPasteboard.general.string(forType: .fileURL) else {
            return nil
        }
        return URL(string: raw)
    }
}
